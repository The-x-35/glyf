import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:eth_sig_util/model/typed_data.dart';
import 'package:eth_sig_util/util/signature.dart';
import 'package:eth_sig_util/util/typed_data.dart';
import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../wallet/wallet_mode.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_wallet.dart';
import 'metamask_link.dart';

/// What a signer is on ("Confirm in MetaMask"), and the link that opens
/// the wallet again while it waits.
typedef SignProgress = void Function(String label, String? reopen);

/// Which wallet signs the keyboard's Ethereum trades.
enum EvmSignerKind {
  glyf('Glyf wallet'),
  metamask('MetaMask');

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
/// by deeplink (metamask_link.dart): Glyf builds each request, MetaMask
/// opens on it and comes back with the answer. Glyf holds no key of
/// MetaMask's, and trusts nothing it sends back until it has checked it here
/// (who signed, who sent, that it landed). Phantom signs only Solana by
/// deeplink, so it isn't one of these (its Solana wallet is lib/wallet/).
abstract final class EvmSigner {
  static final kind = ValueNotifier<EvmSignerKind>(EvmSignerKind.glyf);

  /// The address the chosen wallet signs as; null until there is one.
  static final address = ValueNotifier<String?>(null);

  /// Connected outside wallets, by kind: one address each.
  static final Map<EvmSignerKind, String> _connected = {};

  static String? connected(EvmSignerKind k) => k == EvmSignerKind.glyf ? EvmWallet.address.value : _connected[k];

  static bool _loaded = false;

  /// Reads the switch (WalletModes: the Glyf wallet, or MetaMask for
  /// Ethereum) and what's connected; the signer and its address follow.
  static Future<String?> load() async {
    final s = await GlyfBridge.sharedSettings();
    if (!_loaded) {
      _loaded = true;
      final saved = s['evmWallets'];
      if (saved is Map) {
        for (final e in saved.entries) {
          final k = EvmSignerKind.of(e.key as String?);
          if (k != EvmSignerKind.glyf && e.value is String) _connected[k] = e.value as String;
        }
      }
    }
    WalletModes.mode.value = WalletModes.fromSettings(s);
    await EvmWallet.load();
    return _follow();
  }

  /// Where the switch sends Ethereum signing right now.
  static WalletRoute get route => WalletModes.route(
      solana: false,
      mode: WalletModes.mode.value,
      glyfEvm: EvmWallet.address.value,
      metamask: _connected[EvmSignerKind.metamask]);

  /// The signer the switch picks, written for the keyboard.
  static Future<String?> _follow() async {
    final r = route;
    final k = r.signer == WalletSigner.metamask ? EvmSignerKind.metamask : EvmSignerKind.glyf;
    final changed = k != kind.value || r.address != address.value;
    kind.value = k;
    address.value = r.address;
    if (changed) await _share();
    return address.value;
  }

  /// The switch changed (Profile › Keyboard › Sign with).
  static Future<void> follow() async {
    await load();
    await _share();
  }

  static Future<void> disconnect(EvmSignerKind k) async {
    _connected.remove(k);
    await _follow();
    await _share();
  }

  /// The keyboard reads which wallet and which address: its balances and
  /// "Not enough ETH" are about the wallet that will sign.
  static Future<void> _share() => GlyfBridge.updateSharedSettings((s) {
        s['evmSigner'] = kind.value.name;
        // A phone from before the switch keeps what it had (fromSettings),
        // written down so the keyboard and Keyboard › Sign with agree.
        s['walletMode'] ??= WalletModes.mode.value.name;
        s['evmWallets'] = {for (final e in _connected.entries) e.key.name: e.value};
        if (address.value == null) {
          s.remove('evmAddress');
        } else {
          s['evmAddress'] = address.value;
        }
        return s;
      });

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
    if (k != EvmSignerKind.metamask) throw SignFailed('${k.label} can’t connect');
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
    _connected[k] = _checksum(signer);
    await _follow();
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

  /// Signs and sends [steps] in order with the chosen wallet; each
  /// transaction has to land before the next is asked for.
  static Stream<SignEvent> run(String title, List<SignStep> steps) async* {
    await load();
    final k = kind.value;
    final from = address.value;
    if (from == null) throw SignFailed('No wallet yet', detail: route.missing);
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

  /// MetaMask, by deeplink: each transaction is a trip (it has to land
  /// before the next is asked for); signatures in a row go in one batch.
  static Stream<SignEvent> _runOutside(EvmSignerKind k, String from, String title, List<SignStep> steps) async* {
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
        yield SignEvent.progress('Waiting for ${step.chain.name}…');
        final r = await EvmRpc.receipt(step.chain, hash, timeout: const Duration(seconds: 60));
        if (r == null) {
          if (i == steps.length - 1) {
            out.add(Signed(hash: hash, pending: true));
            i++;
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
        final signer = sig is! String
            ? null
            : switch (s) {
                TypedStep() => recoverTyped(s.map, sig),
                MessageStep(:final message) => recoverMessage(message, sig),
                TxStep() => null,
              };
        if (signer == null || signer.toLowerCase() != from.toLowerCase()) {
          throw SignFailed('That signature isn’t from ${short(from)}');
        }
        out.add(Signed(signature: sig as String));
      }
    }
    yield SignEvent.done(out);
  }

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
