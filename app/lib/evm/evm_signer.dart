import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:eth_sig_util/model/typed_data.dart';
import 'package:eth_sig_util/util/signature.dart';
import 'package:eth_sig_util/util/typed_data.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/keccak.dart';

import '../core/bridge.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'metamask_link.dart';

/// Which wallet signs the keyboard's Ethereum trades. Only outside wallets:
/// Glyf holds no Ethereum key (Arpit, 2026-11-12: "the wallet would be
/// external wallet only").
enum EvmSignerKind {
  metamask('MetaMask');

  const EvmSignerKind(this.label);
  final String label;
}

/// One contract call or transfer for the wallet app to send.
class EvmCall {
  EvmCall({required this.to, this.data, BigInt? value, this.gas}) : value = value ?? BigInt.zero;

  final String to;

  /// 0x calldata, or nil for a plain transfer.
  final String? data;
  final BigInt value;

  /// Known gas, skipping the wallet's own estimate.
  final BigInt? gas;

  static EvmCall fromJson(Map<String, dynamic> j) => EvmCall(
        to: j['to'] as String,
        data: j['data'] as String?,
        value: BigInt.parse((j['value'] ?? '0').toString().replaceFirst('0x', ''),
            radix: (j['value'] ?? '').toString().startsWith('0x') ? 16 : 10),
        gas: j['gas'] == null ? null : BigInt.parse(j['gas'].toString()),
      );
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

/// Hands every Ethereum step to MetaMask by its own deeplinks
/// (metamask_link.dart): Glyf builds each request, MetaMask opens on it,
/// the person approves there, and MetaMask signs and sends. Glyf holds no
/// key, and trusts nothing MetaMask sends back until it has checked it here
/// (who signed, who sent, that it landed). Phantom signs only Solana by
/// deeplink, so it isn't one of these (its Solana wallet is lib/wallet/).
abstract final class EvmSigner {
  /// Always MetaMask: there is no other Ethereum signer.
  static final kind = ValueNotifier<EvmSignerKind>(EvmSignerKind.metamask);

  /// The address MetaMask signs as; null until it is connected.
  static final address = ValueNotifier<String?>(null);

  /// Connected outside wallets, by kind: one address each.
  static final Map<EvmSignerKind, String> _connected = {};

  static String? connected(EvmSignerKind k) => _connected[k];

  /// What to do when there's no wallet to sign with yet.
  static const missing = 'Connect MetaMask in Profile › Wallet';

  static bool _loaded = false;

  /// Reads what's connected; the address follows. Once per launch it also
  /// rewrites what the keyboard reads, so a phone that ran a build with
  /// Glyf's own wallet stops showing that wallet's address and balances.
  static Future<String?> load() async {
    final s = await GlyfBridge.sharedSettings();
    final first = !_loaded;
    if (first) {
      _loaded = true;
      final saved = s['evmWallets'];
      if (saved is Map) {
        for (final e in saved.entries) {
          final k = kindOf(e.key as String?);
          if (k != null && e.value is String) _connected[k] = e.value as String;
        }
      }
    }
    address.value = _connected[EvmSignerKind.metamask];
    if (first && needsRewrite(s, address.value)) await _share();
    return address.value;
  }

  /// Forgets what was read, so the next [load] reads shared settings again.
  @visibleForTesting
  static void reset() {
    _loaded = false;
    _connected.clear();
    address.value = null;
  }

  static EvmSignerKind? kindOf(String? name) {
    for (final k in EvmSignerKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// Whether shared settings say anything other than "MetaMask signs, as
  /// [address]": an older build's Glyf wallet (`evmSigner` glyf, its
  /// `walletMode`), or an address that isn't the connected one.
  @visibleForTesting
  static bool needsRewrite(Map<String, dynamic> s, String? address) =>
      s['evmSigner'] != EvmSignerKind.metamask.name || s.containsKey('walletMode') || s['evmAddress'] != address;

  static Future<void> disconnect(EvmSignerKind k) async {
    _connected.remove(k);
    address.value = _connected[EvmSignerKind.metamask];
    await _share();
  }

  /// The keyboard reads which wallet and which address: its balances and
  /// "Not enough ETH" are about the wallet that will sign.
  static Future<void> _share() => GlyfBridge.updateSharedSettings((s) => shared(s, _connected, address.value));

  /// [s] as the keyboard should read it: MetaMask signs, with [address] (or
  /// no address before it's connected), and no trace of an internal wallet.
  @visibleForTesting
  static Map<String, dynamic> shared(Map<String, dynamic> s, Map<EvmSignerKind, String> wallets, String? address) {
    s['evmSigner'] = EvmSignerKind.metamask.name;
    s.remove('walletMode');
    s['evmWallets'] = {for (final e in wallets.entries) e.key.name: e.value};
    if (address == null) {
      s.remove('evmAddress');
    } else {
      s['evmAddress'] = address;
    }
    return s;
  }

  // MARK: MetaMask

  static Completer<void>? _stop;

  /// Stops waiting on MetaMask (the screen's Stop).
  static void stopWaiting() {
    final s = _stop;
    if (s != null && !s.isCompleted) s.complete();
  }

  /// Connects MetaMask: it asks to connect and signs a one-off message in
  /// the same trip, and the address that signed it is the one kept.
  static Stream<SignEvent> connect(EvmSignerKind k) async* {
    final message = connectMessage(_code());
    final (id, url) = await MetaMaskLink.connectLink(message);
    yield SignEvent.progress('Connect in MetaMask', reopen: MetaMaskLink.home);
    final reply = await _ask(id, url, null);
    yield const SignEvent.progress('Checking…');
    final signature = reply.result is String ? reply.result as String : null;
    final account = reply.accounts.isEmpty ? null : reply.accounts.first;
    if (signature == null || account == null) throw SignFailed('MetaMask didn’t answer');
    final signer = recoverMessage(message, signature);
    if (signer.toLowerCase() != account.toLowerCase()) {
      throw SignFailed('That signature isn’t from ${short(account)}');
    }
    _connected[k] = checksum(signer);
    address.value = _connected[EvmSignerKind.metamask];
    await _share();
    yield const SignEvent.done([]);
  }

  static String connectMessage(String code) => 'Glyf: use this wallet to sign\nCode: $code';

  static String _code() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Opens MetaMask on one request and waits for the answer, saying what
  /// went wrong the way the screen shows it.
  static Future<MetaMaskReply> _ask(String id, String url, String? from) async {
    final stop = _stop = Completer<void>();
    try {
      final reply = await MetaMaskLink.send(id, url, stop: stop.future);
      final e = reply.error;
      if (e != null) throw e;
      return reply;
    } on MetaMaskError catch (e) {
      if (e.refused) throw SignFailed('Stopped in MetaMask', detail: 'Nothing was signed', cancelled: true);
      if (e.changed && from != null) {
        throw SignFailed('MetaMask is on another account', detail: 'Switch to ${short(from)} in MetaMask and try again');
      }
      if (e.unauthorized) throw SignFailed('Connect MetaMask again', detail: 'Profile › Wallet › MetaMask');
      throw SignFailed('MetaMask didn’t sign', detail: e.message);
    } finally {
      if (identical(_stop, stop)) _stop = null;
    }
  }

  /// [rpcs] as one trip to MetaMask on [chain]: led by a chain switch when
  /// MetaMask isn't known to be on it (it refuses anything else on the wrong
  /// chain), as a metamask_batch when there's more than one.
  static Future<(String id, String url, bool switched)> _trip(
      String from, EvmChain chain, List<Map<String, Object?>> rpcs) async {
    final switched = MetaMaskLink.walletChain?.toLowerCase() != MetaMaskLink.hexChain(chain.id);
    final all = [
      if (switched) {'method': 'wallet_switchEthereumChain', 'params': [{'chainId': MetaMaskLink.hexChain(chain.id)}]},
      ...rpcs,
    ];
    final (id, url) = all.length == 1
        ? await MetaMaskLink.requestLink(all.first['method'] as String, all.first['params'] as List<Object?>,
            account: from, chainId: chain.id)
        : await MetaMaskLink.requestLink('metamask_batch', all, account: from, chainId: chain.id);
    return (id, url, switched);
  }

  /// What a trip answered, one result per rpc asked for (the switch's own
  /// answer dropped).
  static List<Object?> _results(MetaMaskReply reply, int asked, bool switched) {
    final r = reply.result;
    final list = asked + (switched ? 1 : 0) == 1 ? [r] : (r is List ? r : const []);
    final mine = switched ? list.skip(1).toList() : list;
    if (mine.length != asked) throw SignFailed('MetaMask stopped part way');
    return mine;
  }

  /// A transaction as eth_sendTransaction takes it.
  static Map<String, Object?> txJson(String from, EvmCall call) => {
        'from': from,
        'to': call.to,
        if (call.data != null && call.data != '0x') 'data': call.data,
        if (call.value > BigInt.zero) 'value': '0x${call.value.toRadixString(16)}',
        if (call.gas != null) 'gas': '0x${call.gas!.toRadixString(16)}',
      };

  /// A signature step as MetaMask takes it.
  static Map<String, Object?> signRpc(String from, SignStep s) => switch (s) {
        TypedStep() => {'method': 'eth_signTypedData_v4', 'params': [from, jsonEncode(s.map)]},
        MessageStep(:final message) => {'method': 'personal_sign', 'params': [MetaMaskLink.hexText(message), from]},
        TxStep() => throw ArgumentError('a transaction is sent, not signed'),
      };

  // MARK: Signing

  /// Asks MetaMask for [steps] in order: each transaction has to land
  /// before the next is asked for; signatures in a row go in one batch.
  static Stream<SignEvent> run(String title, List<SignStep> steps) async* {
    final from = await load();
    if (from == null) throw SignFailed('MetaMask isn’t connected', detail: missing);
    yield* _runOutside(from, steps);
  }

  static Stream<SignEvent> _runOutside(String from, List<SignStep> steps) async* {
    final out = <Signed>[];
    var i = 0;
    while (i < steps.length) {
      final step = steps[i];
      if (step is TxStep) {
        final (id, url, switched) = await _trip(from, step.chain, [
          {'method': 'eth_sendTransaction', 'params': [txJson(from, step.call)]},
        ]);
        yield SignEvent.progress('${step.label}: confirm in MetaMask', reopen: MetaMaskLink.home);
        final reply = await _ask(id, url, from);
        final hash = _results(reply, 1, switched).first;
        if (hash is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash)) {
          throw SignFailed('MetaMask sent nothing for “${step.label}”');
        }
        yield SignEvent.progress('Waiting for ${step.chain.label}…');
        final r = await EvmRpc.receipt(step.chain, hash, timeout: const Duration(seconds: 60));
        if (r == null) {
          if (i == steps.length - 1) {
            out.add(Signed(hash: hash, pending: true));
            i++;
            continue;
          }
          throw SignFailed('${step.label} hasn’t landed', hash: hash, chain: step.chain);
        }
        if (!receiptMatches(r, from: from, to: step.call.to)) {
          throw SignFailed('That transaction isn’t the one asked for', hash: hash, chain: step.chain);
        }
        if (!EvmRpc.succeeded(r)) {
          throw SignFailed(step.failTitle ?? '${step.label} didn’t go through',
              detail: step.failDetail, hash: hash, chain: step.chain);
        }
        out.add(Signed(hash: hash));
        i++;
        continue;
      }
      // Signatures in a row (an order and its permit): one trip.
      final group = <SignStep>[];
      while (i < steps.length && steps[i] is! TxStep && steps[i].chain.id == step.chain.id) {
        group.add(steps[i++]);
      }
      final (id, url, switched) = await _trip(from, step.chain, [for (final s in group) signRpc(from, s)]);
      yield SignEvent.progress(
          group.length == 1 ? '${step.label}: sign in MetaMask' : 'Sign ${group.length} in MetaMask',
          reopen: MetaMaskLink.home);
      final reply = await _ask(id, url, from);
      final got = _results(reply, group.length, switched);
      yield const SignEvent.progress('Checking…');
      for (var j = 0; j < group.length; j++) {
        final s = group[j];
        final sig = got[j];
        if (sig is! String || !signedBy(s, sig, from)) {
          throw SignFailed('That signature isn’t from ${short(from)}');
        }
        out.add(Signed(signature: sig));
      }
    }
    yield SignEvent.done(out);
  }

  // MARK: Checks

  /// A receipt for a transaction MetaMask says it sent: from the connected
  /// address, to the contract Glyf asked for.
  static bool receiptMatches(Map<String, dynamic> r, {required String from, required String to}) =>
      (r['from'] as String? ?? '').toLowerCase() == from.toLowerCase() &&
      (r['to'] as String? ?? '').toLowerCase() == to.toLowerCase();

  /// Whether [signature] over [step] recovers to [from].
  static bool signedBy(SignStep step, String signature, String from) {
    try {
      final signer = switch (step) {
        TypedStep() => recoverTyped(step.map, signature),
        MessageStep(:final message) => recoverMessage(message, signature),
        TxStep() => null,
      };
      return signer != null && signer.toLowerCase() == from.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  static String recoverTyped(Map<String, dynamic> typed, String signature) {
    final hash = TypedDataUtil.hashTypedDataV4(TypedMessage.fromJson(typed));
    return SignatureUtil.ecRecover(signature: signature, message: hash, isPersonalSign: false);
  }

  static String recoverMessage(String message, String signature) => SignatureUtil.ecRecover(
      signature: signature, message: Uint8List.fromList(utf8.encode(message)), isPersonalSign: true);

  static String short(String a) => a.length < 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

  /// [a] with its EIP-55 checksum; [a] as given when it isn't an address.
  static String checksum(String a) {
    final hex = a.toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hex)) return a;
    final digest = KeccakDigest(256).process(Uint8List.fromList(utf8.encode(hex)));
    final out = StringBuffer('0x');
    for (var i = 0; i < 40; i++) {
      final nibble = (digest[i ~/ 2] >> (i.isEven ? 4 : 0)) & 0xf;
      out.write(nibble >= 8 ? hex[i].toUpperCase() : hex[i]);
    }
    return out.toString();
  }
}
