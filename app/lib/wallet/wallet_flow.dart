import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import 'base58.dart';
import 'phantom.dart';
import 'solana.dart';
import 'wallet_api.dart';

/// The Keychain (iPhone) or a Keystore-sealed file (Android), through the
/// bridge: the Phantom session and our half of its encryption.
class BridgeSecrets implements SecretStore {
  @override
  Future<String?> load(String name) => GlyfBridge.walletSecretLoad(name);
  @override
  Future<void> save(String name, String value) => GlyfBridge.walletSecretSave(name, value);
  @override
  Future<void> clear(String name) => GlyfBridge.walletSecretClear(name);
}

enum PayKind { send, private, buy }

/// A payment built and waiting on Phantom. Kept on disk, because iOS may
/// close Glyf while Phantom is open.
class PendingPay {
  const PendingPay({required this.id, required this.kind, required this.summary, this.requestId});

  final String id;
  final PayKind kind;

  /// "5 USDC to 7dHb…7ARj", "≈ 333,175 BONK".
  final String summary;

  /// Jupiter's, for /execute.
  final String? requestId;

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'summary': summary, 'requestId': requestId};

  static PendingPay? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = PayKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null || json['id'] is! String) return null;
    return PendingPay(
      id: json['id'] as String,
      kind: kind,
      summary: json['summary'] as String? ?? '',
      requestId: json['requestId'] as String?,
    );
  }
}

/// How a payment ended, for the status screen.
class PayOutcome {
  const PayOutcome({required this.state, required this.title, this.detail, this.signature, this.kind});

  final PayState state;
  final String title;
  final String? detail;
  final String? signature;
  final PayKind? kind;
}

/// `submitted`: it left for Solana, but Glyf couldn't confirm it landed.
enum PayState { working, done, submitted, failed, cancelled }

/// The wallet, end to end: Phantom holds the keys and signs; Glyf builds
/// each transaction on the phone and sends the signed one on (Solana for a
/// send, MagicBlock for a private one, Jupiter for a buy). No key that can
/// move money is ever in Glyf.
abstract final class WalletFlow {
  static final phantom = Phantom(BridgeSecrets());

  /// The connected wallet, or null.
  static final link = ValueNotifier<PhantomLink?>(null);

  static const _pendingName = 'phantom-pending-pay';
  static const phantomAppStore = 'https://apps.apple.com/app/phantom-crypto-wallet/id1598432977';
  static const phantomPlayStore = 'https://play.google.com/store/apps/details?id=app.phantom';

  static Future<void> load() async {
    link.value = await phantom.link();
  }

  /// Opens Phantom to connect. An error to show, or null.
  static Future<String?> connect() async {
    Telemetry.log('wallet_connect_started', {});
    return _open(await phantom.connectUrl());
  }

  /// Forgets the wallet on this phone. Phantom lists Glyf under its
  /// connected apps until it's removed there too.
  static Future<void> disconnect() async {
    await phantom.forget();
    await BridgeSecrets().clear(_pendingName);
    link.value = null;
    await _shareAddress(null);
    Telemetry.log('wallet_disconnected', {});
  }

  /// Builds a send and opens Phantom to sign it. An error to show, or null.
  static Future<String?> send({
    required String to,
    required String amount,
    required TokenInfo token,
    bool private = false,
  }) async {
    final wallet = link.value ?? await phantom.link();
    if (wallet == null) return 'Connect Phantom first';
    final recipient = to.trim();
    if (!Sol.isAddress(recipient)) return 'That isn’t a Solana address';
    if (recipient == wallet.address) return 'That’s your own wallet';
    final units = Sol.units(amount, token.decimals);
    if (units == null) return 'Enter an amount';
    try {
      // Everything Solana is asked at once — the checks used to run one
      // after the other, and the trip to Phantom felt like a wait.
      final ownerF = SolanaRpc.owner(recipient);
      final solF = SolanaRpc.solBalance(wallet.address);
      final haveF = token.mint == Sol.wsol ? solF : SolanaRpc.tokenBalance(wallet.address, token.mint);
      final hashF = private ? null : SolanaRpc.blockhash();
      // An early refusal below leaves the others running; their failures
      // are nobody's news then.
      solF.ignore();
      haveF.ignore();
      hashF?.ignore();
      // Money sent to a token's or an app's address is gone for good: only
      // a wallet (the System Program's, or one never paid yet) is paid.
      final owner = await ownerF;
      if (owner == Sol.tokenProgram || owner == Sol.token2022Program) return 'That’s a token’s address, not a wallet';
      if (owner != null && owner != Sol.systemProgram) return 'That isn’t a wallet address';
      // What Phantom would refuse anyway, said before the trip there.
      final short = _shortfall(await solF, await haveF, units, token, private: private);
      if (short != null) return short;
      final Uint8List tx;
      if (private) {
        tx = await MagicBlock.privateTransfer(from: wallet.address, to: recipient, amount: units, mint: token.mint);
      } else if (token.mint == Sol.wsol) {
        tx = Sol.transferSol(from: wallet.address, to: recipient, lamports: units, blockhash: await hashF!);
      } else {
        tx = Sol.transferToken(
          from: wallet.address,
          to: recipient,
          mint: token.mint,
          amount: units,
          decimals: token.decimals,
          blockhash: await hashF!,
        );
      }
      final pending = PendingPay(
        id: _newId(),
        kind: private ? PayKind.private : PayKind.send,
        summary:
            '${Sol.format(units, token.decimals, maxDecimals: token.decimals)} ${token.symbol} to ${Sol.short(recipient)}',
      );
      await BridgeSecrets().save(_pendingName, jsonEncode(pending.toJson()));
      Telemetry.log('wallet_send_started', {'private': private, 'token': token.symbol});
      return _open(await phantom.signUrl(tx, pending.id));
    } on WalletError catch (e) {
      return e.message;
    } on PhantomError catch (e) {
      return e.message;
    } catch (_) {
      // A reply that wasn't JSON, TLS, a dropped connection: Phantom was
      // never opened, so nothing moved.
      return _unexpected;
    }
  }

  static const _unexpected = 'Something went wrong. Try again';

  /// For a break nobody planned for once Phantom has signed: whether money
  /// moved isn't known, so nobody should simply try again.
  static const unknownOutcome =
      PayOutcome(state: PayState.failed, title: 'Something went wrong', detail: 'Check Phantom before trying again');

  /// Buys [token] with [amount] of [payWith] through Jupiter, signed in
  /// Phantom. An error to show, or null.
  static Future<String?> buy({required TokenInfo token, required TokenInfo payWith, required String amount}) async {
    final wallet = link.value ?? await phantom.link();
    if (wallet == null) return 'Connect Phantom first';
    final units = Sol.units(amount, payWith.decimals);
    if (units == null) return 'Enter an amount';
    try {
      final order = await Jupiter.order(
        inputMint: payWith.mint,
        outputMint: token.mint,
        amount: units,
        taker: wallet.address,
      );
      final tx = order.transaction;
      if (tx == null) return 'Jupiter can’t make that swap right now';
      final pending = PendingPay(
        id: _newId(),
        kind: PayKind.buy,
        summary: '${Sol.format(order.outAmount, token.decimals, maxDecimals: 2)} ${token.symbol}',
        requestId: order.requestId,
      );
      await BridgeSecrets().save(_pendingName, jsonEncode(pending.toJson()));
      Telemetry.log('wallet_buy_started', {'token': token.symbol, 'payWith': payWith.symbol});
      return _open(await phantom.signUrl(base64.decode(tx), pending.id));
    } on WalletError catch (e) {
      return e.message;
    } on PhantomError catch (e) {
      return e.message;
    } catch (_) {
      return _unexpected;
    }
  }

  /// Phantom's reply (glyf://phantom/…), taken through to the end. Every
  /// path ends in an outcome, whatever breaks on the way (a proxy's HTML
  /// 502, TLS, a reply of the wrong shape): never a screen left on Sending….
  static Stream<PayOutcome> handleReply(Uri reply) async* {
    final step = reply.pathSegments.isEmpty ? '' : reply.pathSegments.first;
    if (step == 'connect') {
      try {
        final wallet = await phantom.finishConnect(reply);
        link.value = wallet;
        await _shareAddress(wallet.address);
        Telemetry.log('wallet_connected', {});
        yield await _told(PayOutcome(
            state: PayState.done, title: 'Phantom connected', detail: Sol.short(wallet.address)));
      } on PhantomError catch (e) {
        yield await _told(PayOutcome(
          state: e.cancelled ? PayState.cancelled : PayState.failed,
          title: e.cancelled ? 'Not connected' : 'Couldn’t connect',
          detail: e.cancelled ? null : e.message,
        ));
      } catch (_) {
        yield await _told(
            const PayOutcome(state: PayState.failed, title: 'Couldn’t connect', detail: 'Try again from Glyf'));
      }
      return;
    }
    if (step != 'sign' || reply.pathSegments.length < 2) {
      // Nothing Glyf is waiting on (a disconnect, a link it never made),
      // but the screen still needs an end.
      yield const PayOutcome(state: PayState.cancelled, title: 'Nothing to finish', detail: 'Start again from Glyf');
      return;
    }

    PendingPay? pending;
    try {
      final raw = await BridgeSecrets().load(_pendingName);
      pending = raw == null ? null : PendingPay.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable is as good as gone: nothing was sent.
    }
    if (pending == null || pending.id != reply.pathSegments[1]) {
      yield const PayOutcome(state: PayState.failed, title: 'That payment expired', detail: 'Start it again from Glyf');
      return;
    }
    final verb = pending.kind == PayKind.buy ? 'Buying' : 'Sending';
    yield PayOutcome(state: PayState.working, title: '$verb…', detail: pending.summary, kind: pending.kind);
    // Set once the payment has left: from then on nothing may say it didn't.
    String? signature;
    // The transaction's own signature, known before it is sent.
    String? expected;
    try {
      final signed = await phantom.finishSign(reply);
      expected = txSignature(signed);
      signature = switch (pending.kind) {
        PayKind.send => await SolanaRpc.send(signed),
        PayKind.private => await MagicBlock.send(signed),
        PayKind.buy => await Jupiter.execute(signed, pending.requestId ?? ''),
      };
      if (pending.kind == PayKind.send && await SolanaRpc.confirm(signature) == false) {
        yield await _told(PayOutcome(
          state: PayState.failed,
          title: 'Didn’t go through',
          detail: 'Solana turned it down. Nothing was sent',
          signature: signature,
          kind: pending.kind,
        ));
      } else {
        Telemetry.log('wallet_${pending.kind.name}_done', {});
        yield await _told(PayOutcome(
          state: PayState.done,
          title: switch (pending.kind) {
            PayKind.buy => 'Bought',
            PayKind.private => 'Sent privately',
            PayKind.send => 'Sent',
          },
          detail: pending.summary,
          signature: signature,
          kind: pending.kind,
        ));
      }
    } on PhantomError catch (e) {
      yield await _told(PayOutcome(
        state: e.cancelled ? PayState.cancelled : PayState.failed,
        title: e.cancelled ? 'Cancelled in Phantom' : 'Phantom couldn’t sign it',
        detail: e.cancelled ? 'Nothing was sent' : e.message,
        kind: pending.kind,
      ));
    } catch (e) {
      // No answer to the send itself (a timeout, a gateway's error page): it
      // may still have reached Solana, so its own signature is what to look
      // up. "Try again" there could pay twice. Private sends go through
      // MagicBlock's own chain, where that signature means nothing to Solscan.
      if (signature == null && expected != null && pending.kind != PayKind.private && _mayHaveLeft(e)) {
        signature = expected;
      }
      if (signature != null) {
        // It left for Solana; only the check on it failed. "Didn't go
        // through" here would have people pay twice.
        yield await _told(PayOutcome(
          state: PayState.submitted,
          title: 'Submitted',
          detail: '${pending.summary} · not confirmed yet',
          signature: signature,
          kind: pending.kind,
        ));
      } else if (e is WalletError) {
        yield await _told(
            PayOutcome(state: PayState.failed, title: 'Didn’t go through', detail: e.message, kind: pending.kind));
      } else {
        yield await _told(unknownOutcome);
      }
    } finally {
      await BridgeSecrets().clear(_pendingName);
    }
  }

  /// Where anyone can look a transaction up.
  static String solscanUrl(String signature) => 'https://solscan.io/tx/$signature';

  /// A signed transaction's id: its first signature, the 64 bytes after the
  /// signature count (Solana's wire format), in base58.
  @visibleForTesting
  static String? txSignature(Uint8List signed) =>
      signed.length > 65 && signed[0] >= 1 ? Base58.encode(signed.sublist(1, 65)) : null;

  /// A failure that says nothing about whether Solana took the payment: no
  /// answer in time, or a page that isn't the node's answer. A refusal in
  /// the node's own words (no funds, simulation failed) means it didn't.
  static bool _mayHaveLeft(Object e) =>
      e is TimeoutException || e is FormatException ||
      (e is WalletError && e.message == 'Solana didn’t answer. Try again');

  /// Why the wallet can't send [units] of [token], or null when it can. A
  /// send costs about 0.000005 SOL; a private one about 0.002 SOL more.
  static String? _shortfall(BigInt sol, BigInt have, BigInt units, TokenInfo token, {bool private = false}) {
    final fee = BigInt.from(private ? 2100000 : 10000);
    if (token.mint == Sol.wsol) {
      if (units + fee <= sol) return null;
      return sol == BigInt.zero ? 'You have no SOL' : 'You only have ${Sol.format(sol, Sol.solDecimals)} SOL';
    }
    if (units > have) {
      return have == BigInt.zero
          ? 'You have no ${token.symbol}'
          : 'You only have ${Sol.format(have, token.decimals, maxDecimals: 2)} ${token.symbol}';
    }
    if (sol < fee) {
      return private ? 'A private send needs about 0.002 SOL for fees' : 'Add a little SOL for the network fee';
    }
    return null;
  }

  /// How it went, written where the keyboard reads (shared settings): back
  /// in the chat, the keyboard says it once and clears it.
  static Future<PayOutcome> _told(PayOutcome o) async {
    // Not confirmed: the keyboard's line carries the link to check it by.
    final detail = [
      ?o.detail,
      if (o.state == PayState.submitted && o.signature != null) solscanUrl(o.signature!),
    ].join(' · ');
    try {
      await GlyfBridge.updateSharedSettings((s) {
        s['walletOutcome'] = jsonEncode({
          'title': o.title,
          if (detail.isNotEmpty) 'detail': detail,
          'signature': ?o.signature,
          'at': DateTime.now().millisecondsSinceEpoch / 1000.0,
        });
        return s;
      });
    } catch (_) {
      // A toast the keyboard misses is no reason to fail the payment.
    }
    return o;
  }

  /// Phantom, or its App Store page when it isn't installed.
  static Future<String?> _open(Uri url) async {
    // Debug builds log the link, so a stand-in Phantom can answer it on a
    // simulator (Phantom itself only runs on a phone). In pieces: the
    // system log cuts a line at 1024 bytes.
    if (kDebugMode) {
      final link = url.toString();
      final n = (link.length / 700).ceil();
      for (var i = 0; i < n; i++) {
        debugPrint('GLYF_PHANTOM $i/$n ${link.substring(i * 700, min((i + 1) * 700, link.length))}');
      }
    }
    if (await GlyfBridge.openPhantom(url.toString())) return null;
    await GlyfBridge.openURL(defaultTargetPlatform == TargetPlatform.iOS ? phantomAppStore : phantomPlayStore);
    return 'Install Phantom, then try again';
  }

  /// The keyboard shows the connected address (public, never a key).
  static Future<void> _shareAddress(String? address) => GlyfBridge.updateSharedSettings((s) {
    if (address == null) {
      s.remove('walletAddress');
    } else {
      s['walletAddress'] = address;
    }
    return s;
  });

  static String _newId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}
