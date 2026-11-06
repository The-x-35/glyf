import 'dart:async';
import 'dart:convert';

import 'package:eth_sig_util/model/typed_data.dart';
import 'package:eth_sig_util/util/signature.dart';
import 'package:eth_sig_util/util/typed_data.dart';
import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_wallet.dart';

/// What a signer is on ("Confirm in MetaMask"), and the link that opens
/// the wallet again while it waits.
typedef SignProgress = void Function(String label, String? reopen);

/// Which wallet signs the keyboard's Ethereum trades.
enum EvmSignerKind {
  glyf('Glyf wallet'),
  metamask('MetaMask'),
  phantom('Phantom');

  const EvmSignerKind(this.label);
  final String label;

  static EvmSignerKind of(String? name) =>
      EvmSignerKind.values.firstWhere((k) => k.name == name, orElse: () => EvmSignerKind.glyf);
}

/// One thing to sign, in the order a trade needs it.
sealed class SignStep {
  const SignStep(this.chain, this.label);
  final EvmChain chain;

  /// What the person is agreeing to ("Let Uniswap use your USDC").
  final String label;
}

class TxStep extends SignStep {
  const TxStep(super.chain, super.label, this.call, {this.failTitle, this.failDetail});
  final EvmCall call;

  /// What the screen says when this one reverts.
  final String? failTitle;
  final String? failDetail;
}

class TypedStep extends SignStep {
  const TypedStep(super.chain, super.label, this.typed);

  /// EIP-712 typed data, as JSON text or a map.
  final Object typed;

  Map<String, dynamic> get map =>
      Map<String, dynamic>.from(typed is String ? jsonDecode(typed as String) as Map : typed as Map);
}

/// A plain message (EIP-191 personal_sign), like Flash's cancel.
class MessageStep extends SignStep {
  const MessageStep(super.chain, super.label, this.message);
  final String message;
}

/// What a step came back with: a transaction's hash or a signature.
class Signed {
  const Signed({this.hash, this.signature, this.pending = false});
  final String? hash;
  final String? signature;

  /// The last transaction was sent but hadn't landed when the wait ran out.
  final bool pending;
}

/// Progress on the way (a label to show), or the finished list.
class SignEvent {
  const SignEvent.progress(this.label, {this.reopen}) : results = null;
  const SignEvent.done(List<Signed> this.results)
      : label = null,
        reopen = null;
  final String? label;
  final List<Signed>? results;

  /// Opens the wallet again, while it's waiting on one.
  final String? reopen;
}

/// A step that didn't happen: refused in the wallet, reverted, or answered
/// with something that doesn't check out.
class SignFailed implements Exception {
  SignFailed(this.title, {this.detail, this.hash, this.chain, this.cancelled = false});
  final String title;
  final String? detail;
  final String? hash;
  final EvmChain? chain;
  final bool cancelled;
  @override
  String toString() => detail == null ? title : '$title. $detail';
}

/// Signs with the Glyf wallet on the phone, or hands the steps to MetaMask
/// or Phantom: a page of Glyf's opens in the wallet's own browser, the
/// wallet signs there, and the answers come back through the server. Glyf
/// holds no key of an outside wallet, and trusts nothing the page sends
/// back until it has checked it here (who signed, who sent, that it landed).
abstract final class EvmSigner {
  static final kind = ValueNotifier<EvmSignerKind>(EvmSignerKind.glyf);

  /// The address the chosen wallet signs as; null until there is one.
  static final address = ValueNotifier<String?>(null);

  /// Connected outside wallets, by kind: one address each.
  static final Map<EvmSignerKind, String> _connected = {};

  static String? connected(EvmSignerKind k) => k == EvmSignerKind.glyf ? EvmWallet.address.value : _connected[k];

  static bool _loaded = false;

  static Future<String?> load() async {
    if (!_loaded) {
      _loaded = true;
      final s = await GlyfBridge.sharedSettings();
      kind.value = EvmSignerKind.of(s['evmSigner'] as String?);
      final saved = s['evmWallets'];
      if (saved is Map) {
        for (final e in saved.entries) {
          final k = EvmSignerKind.of(e.key as String?);
          if (k != EvmSignerKind.glyf && e.value is String) _connected[k] = e.value as String;
        }
      }
    }
    await EvmWallet.load();
    address.value = connected(kind.value);
    return address.value;
  }

  /// Signs with [k] from now on (an outside wallet only once it's connected).
  static Future<void> choose(EvmSignerKind k) async {
    if (k != EvmSignerKind.glyf && _connected[k] == null) return;
    kind.value = k;
    if (k == EvmSignerKind.glyf) await EvmWallet.ensure();
    address.value = connected(k);
    await _share();
  }

  static Future<void> disconnect(EvmSignerKind k) async {
    _connected.remove(k);
    if (kind.value == k) kind.value = EvmSignerKind.glyf;
    address.value = connected(kind.value);
    await _share();
  }

  /// The keyboard reads which wallet and which address: its balances and
  /// "Not enough ETH" are about the wallet that will sign.
  static Future<void> _share() => GlyfBridge.updateSharedSettings((s) {
        s['evmSigner'] = kind.value.name;
        s['evmWallets'] = {for (final e in _connected.entries) e.key.name: e.value};
        if (address.value == null) {
          s.remove('evmAddress');
        } else {
          s['evmAddress'] = address.value;
        }
        return s;
      });

  // MARK: Outside wallets

  /// The link that opens [url] in the wallet's own browser.
  static String walletLink(EvmSignerKind k, String url) => switch (k) {
        EvmSignerKind.metamask => 'https://metamask.app.link/dapp/${url.replaceFirst(RegExp(r'^https?://'), '')}',
        EvmSignerKind.phantom =>
          'https://phantom.app/ul/browse/${Uri.encodeComponent(url)}?ref=${Uri.encodeComponent(Uri.parse(url).origin)}',
        EvmSignerKind.glyf => url,
      };

  static Completer<void>? _stop;

  /// Stops waiting on the wallet (the screen's Stop).
  static void stopWaiting() => _stop?.complete();

  /// Connects [k]: the wallet signs a one-off message naming the job, and
  /// the address that signed it is the one kept.
  static Stream<SignEvent> connect(EvmSignerKind k) async* {
    final job = await GlyfApi.evmPost('/wallet-jobs', {'kind': 'connect', 'wallet': k.name, 'title': 'Connect ${k.label}'});
    final id = job['id'] as String;
    final link = walletLink(k, job['url'] as String);
    await GlyfBridge.openURL(link);
    yield SignEvent.progress('Connect in ${k.label}', reopen: link);
    final answer = await _await(id, k, link, (label) {});
    yield SignEvent.progress('Checking…');
    final address = answer['address'] as String?;
    final results = (answer['results'] as List? ?? const []).cast<Map>();
    final signature = results.isEmpty ? null : results.first['signature'] as String?;
    if (address == null || signature == null) throw SignFailed('${k.label} didn’t answer');
    final signer = recoverMessage(connectMessage(id), signature);
    if (signer.toLowerCase() != address.toLowerCase()) {
      throw SignFailed('That signature isn’t from ${short(address)}');
    }
    _connected[k] = _checksum(address);
    kind.value = k;
    EvmSigner.address.value = _connected[k];
    await _share();
    yield const SignEvent.done([]);
  }

  /// Must match lib/walletjobs.ts connectMessage on the server.
  static String connectMessage(String id) => 'Glyf: use this wallet to sign\nCode: $id';

  /// Waits for the page to finish (polling the server), and says when the
  /// wallet has sent something so the screen can follow along.
  static Future<Map<String, dynamic>> _await(
      String id, EvmSignerKind k, String link, void Function(String label) onProgress) async {
    final stop = _stop = Completer<void>();
    final end = DateTime.now().add(const Duration(minutes: 30));
    var seen = 0;
    try {
      while (DateTime.now().isBefore(end)) {
        if (stop.isCompleted) throw SignFailed('Stopped', detail: 'Nothing more was asked of ${k.label}', cancelled: true);
        Map<String, dynamic>? res;
        try {
          res = await GlyfApi.evmGet('/wallet-jobs/$id');
        } on GlyfApiException {
          res = null; // a dropped poll is no reason to stop waiting
        }
        if (res != null) {
          final results = (res['results'] as List? ?? const []);
          if (results.length > seen) {
            seen = results.length;
            onProgress('$seen done in ${k.label}');
          }
          switch (res['status']) {
            case 'done':
              return res;
            case 'cancelled':
              throw SignFailed('Stopped in ${k.label}', detail: res['error'] as String?, cancelled: true);
            case 'failed':
              throw SignFailed('That didn’t go through', detail: res['error'] as String?);
          }
        }
        await Future.any([Future<void>.delayed(const Duration(milliseconds: 1500)), stop.future]);
      }
      throw SignFailed('${k.label} took too long', detail: 'Start again from the keyboard');
    } finally {
      if (identical(_stop, stop)) _stop = null;
    }
  }

  // MARK: Signing

  /// Signs and sends [steps] in order with the chosen wallet; each
  /// transaction has to land before the next is asked for.
  static Stream<SignEvent> run(String title, List<SignStep> steps) async* {
    await load();
    final k = kind.value;
    final from = address.value;
    if (from == null) throw SignFailed('No wallet yet', detail: 'Make one or connect one in Profile › Wallet › Ethereum');
    if (k == EvmSignerKind.glyf) {
      yield* _runHere(steps);
    } else {
      yield* _runOutside(k, from, title, steps);
    }
  }

  static Stream<SignEvent> _runHere(List<SignStep> steps) async* {
    final out = <Signed>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      yield SignEvent.progress('${step.label}…');
      switch (step) {
        case TxStep():
          final hash = await EvmWallet.send(step.chain, step.call);
          final r = await EvmRpc.receipt(step.chain, hash);
          if (r == null && i == steps.length - 1) {
            out.add(Signed(hash: hash, pending: true));
            continue;
          }
          if (r == null || !EvmRpc.succeeded(r)) {
            throw SignFailed(step.failTitle ?? '${step.label} didn’t go through',
                detail: step.failDetail, hash: hash, chain: step.chain);
          }
          out.add(Signed(hash: hash));
        case TypedStep():
          out.add(Signed(signature: EvmWallet.signTypedData(step.map)));
        case MessageStep():
          out.add(Signed(signature: EvmWallet.signMessage(Uint8List.fromList(utf8.encode(step.message)))));
      }
    }
    yield SignEvent.done(out);
  }

  static Stream<SignEvent> _runOutside(EvmSignerKind k, String from, String title, List<SignStep> steps) async* {
    final job = await GlyfApi.evmPost('/wallet-jobs', {
      'kind': 'run',
      'wallet': k.name,
      'title': title,
      'from': from,
      'steps': [for (final s in steps) stepJson(s)],
    });
    final id = job['id'] as String;
    final link = walletLink(k, job['url'] as String);
    await GlyfBridge.openURL(link);
    yield SignEvent.progress('Confirm in ${k.label}', reopen: link);
    final progress = StreamController<SignEvent>();
    final answer = _await(id, k, link, (label) => progress.add(SignEvent.progress(label, reopen: link)));
    unawaited(answer.whenComplete(progress.close).then((_) {}, onError: (_) {}));
    yield* progress.stream;
    final res = await answer;
    yield const SignEvent.progress('Checking…');
    final results = (res['results'] as List? ?? const []).cast<Map>();
    if (results.length != steps.length) throw SignFailed('${k.label} stopped part way');
    final out = <Signed>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final got = results[i];
      switch (step) {
        case TxStep():
          final hash = got['hash'] as String?;
          if (hash == null) throw SignFailed('${k.label} sent nothing for “${step.label}”');
          final r = await EvmRpc.receipt(step.chain, hash, timeout: const Duration(seconds: 30));
          if (r == null) {
            if (i == steps.length - 1) {
              out.add(Signed(hash: hash, pending: true));
              continue;
            }
            throw SignFailed('${step.label} hasn’t landed', hash: hash, chain: step.chain);
          }
          final sender = (r['from'] as String? ?? '').toLowerCase();
          final to = (r['to'] as String? ?? '').toLowerCase();
          if (sender != from.toLowerCase() || to != step.call.to.toLowerCase()) {
            throw SignFailed('That transaction isn’t the one asked for', hash: hash, chain: step.chain);
          }
          if (!EvmRpc.succeeded(r)) {
            throw SignFailed(step.failTitle ?? '${step.label} didn’t go through',
                detail: step.failDetail, hash: hash, chain: step.chain);
          }
          out.add(Signed(hash: hash));
        case TypedStep():
          final sig = got['signature'] as String?;
          if (sig == null || recoverTyped(step.map, sig).toLowerCase() != from.toLowerCase()) {
            throw SignFailed('That signature isn’t from ${short(from)}');
          }
          out.add(Signed(signature: sig));
        case MessageStep():
          final sig = got['signature'] as String?;
          if (sig == null || recoverMessage(step.message, sig).toLowerCase() != from.toLowerCase()) {
            throw SignFailed('That signature isn’t from ${short(from)}');
          }
          out.add(Signed(signature: sig));
      }
    }
    yield SignEvent.done(out);
  }

  /// A step as the server's job takes it (routes/walletjobs.ts).
  static Map<String, Object?> stepJson(SignStep s) => switch (s) {
        TxStep(:final call) => {
            'type': 'tx',
            'chainId': s.chain.id,
            'to': call.to,
            if (call.data != null) 'data': call.data,
            if (call.value > BigInt.zero) 'value': call.value.toString(),
            if (call.gas != null) 'gas': call.gas.toString(),
            'label': s.label,
          },
        TypedStep() => {'type': 'typed', 'chainId': s.chain.id, 'data': s.map, 'label': s.label},
        MessageStep(:final message) => {'type': 'message', 'message': message, 'label': s.label},
      };

  // MARK: Checks

  static String recoverTyped(Map<String, dynamic> typed, String signature) {
    final hash = TypedDataUtil.hashTypedDataV4(TypedMessage.fromJson(typed));
    return SignatureUtil.ecRecover(signature: signature, message: hash, isPersonalSign: false);
  }

  static String recoverMessage(String message, String signature) => SignatureUtil.ecRecover(
      signature: signature, message: Uint8List.fromList(utf8.encode(message)), isPersonalSign: true);

  static String short(String a) => a.length < 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

  static String _checksum(String a) {
    try {
      return EvmWallet.checksum(a);
    } catch (_) {
      return a;
    }
  }
}
