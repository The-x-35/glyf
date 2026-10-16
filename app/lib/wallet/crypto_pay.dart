import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/bridge.dart';
import '../core/flavor.dart';
import '../core/glyf_api.dart';
import 'mwa.dart';
import 'solana.dart';
import 'wallet_api.dart';
import 'wallet_flow.dart';

/// A Solana Pay request from the server: USDC to Glyf's treasury, with a
/// one-off reference the server finds the payment by.
class CryptoRequest {
  const CryptoRequest({
    required this.reference,
    required this.recipient,
    required this.mint,
    required this.amount,
    required this.url,
  });

  final String reference;
  final String recipient;
  final String mint;

  /// Whole USDC, "2".
  final String amount;

  /// solana:… for any wallet that opens Solana Pay links.
  final String url;

  static CryptoRequest? fromJson(Map<String, dynamic> json) {
    final r = json['reference'], to = json['recipient'], m = json['mint'], a = json['amount'], u = json['url'];
    if (r is! String || to is! String || m is! String || a is! String || u is! String) return null;
    return CryptoRequest(reference: r, recipient: to, mint: m, amount: a, url: u);
  }
}

/// Plus and Max paid in USDC (docs/CRYPTO-PAYMENTS.md).
///
/// Only the Solana dApp Store build offers it: Android, `--flavor dappStore`
/// (or `--dart-define=GLYF_CRYPTO_PAY=true` on any Android build but Play's,
/// for testing), and only while the server says it's on (GLYF_TREASURY set
/// there). The App Store and Google Play builds never show it: both stores
/// require their own billing for subscriptions bought inside the app, so
/// the Play flavor ignores the define.
///
/// The phone signs over Mobile Wallet Adapter when it has a wallet (Seed
/// Vault on a Seeker, Phantom, Solflare), and otherwise opens the Solana
/// Pay link in whichever wallet takes it. Either way the server checks the
/// transfer on Solana before the plan changes.
abstract final class CryptoPay {
  static const buildFlag = bool.fromEnvironment('GLYF_CRYPTO_PAY');

  static bool get allowed => Platform.isAndroid && (Flavor.dappStore || (buildFlag && !Flavor.play));

  /// Whether to offer it: this build may, and the server takes it.
  static Future<bool> available() async {
    if (!allowed) return false;
    try {
      return (await GlyfApi.cryptoConfig())['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<CryptoRequest> request(String plan, {required bool yearly}) async {
    final res = await GlyfApi.cryptoRequest(plan, yearly ? 'year' : 'month');
    final req = CryptoRequest.fromJson(res);
    if (req == null) throw GlyfApiException('Couldn’t start the payment');
    return req;
  }

  /// The USDC transfer, the way Solana Pay builds one: the treasury's
  /// token account opened if it has none, then TransferChecked with the
  /// reference added as a read-only account the server searches by.
  static Uint8List transfer({required String from, required CryptoRequest request, required String blockhash}) {
    final units = Sol.units(request.amount, Sol.usdcDecimals)!;
    final source = Sol.tokenAccount(from, request.mint);
    final destination = Sol.tokenAccount(request.recipient, request.mint);
    return Sol.compileLegacy(
      feePayer: from,
      blockhash: blockhash,
      instructions: [
        Instruction(
          Sol.ataProgram,
          [
            AccountMeta(from, signer: true, writable: true),
            AccountMeta(destination, writable: true),
            AccountMeta(request.recipient),
            AccountMeta(request.mint),
            const AccountMeta(Sol.systemProgram),
            const AccountMeta(Sol.tokenProgram),
          ],
          const [1],
        ),
        Instruction(
          Sol.tokenProgram,
          [
            AccountMeta(source, writable: true),
            AccountMeta(request.mint),
            AccountMeta(destination, writable: true),
            AccountMeta(from, signer: true),
            AccountMeta(request.reference),
          ],
          [12, ..._u64(units), Sol.usdcDecimals],
        ),
      ],
    );
  }

  /// Hands the payment to a wallet. Null once it's on its way (signed and
  /// sent here, or the wallet opened); '' when the person backed out;
  /// otherwise what to show.
  static Future<String?> pay(CryptoRequest request) async {
    if (await Mwa.isAvailable()) {
      Uint8List? tx;
      try {
        final account = await WalletFlow.mwa.load() ?? await WalletFlow.mwa.connect();
        if (account == null) return '';
        final blockhash = await SolanaRpc.blockhash();
        tx = transfer(from: account.address, request: request, blockhash: blockhash);
      } on MwaException catch (e) {
        if (e.cancelled) return '';
      } catch (_) {
        // Nothing was signed: the link below may still work.
      }
      if (tx != null) {
        try {
          final signed = await WalletFlow.mwa.sign(tx);
          await SolanaRpc.send(signed);
          return null;
        } on MwaException catch (e) {
          return e.cancelled ? '' : e.message;
        } on WalletError catch (e) {
          return e.message;
        } catch (_) {
          return 'The wallet couldn’t send it. Nothing was paid';
        }
      }
    }
    return await GlyfBridge.openURL(request.url) ? null : 'Install a Solana wallet, like Phantom';
  }

  /// Asks the server until the transfer lands: the plan now on the
  /// account, or throws with what to show. Null when [giveUp] passes first;
  /// the request is kept, and [resume] asks again at the next launch.
  static Future<String?> waitForPlan(String reference, {Duration giveUp = const Duration(minutes: 3)}) async {
    await _keep(reference);
    final end = DateTime.now().add(giveUp);
    var refusals = 0;
    while (DateTime.now().isBefore(end)) {
      try {
        final plan = await _check(reference);
        if (plan != null) return plan;
        refusals = 0;
      } on GlyfApiException {
        // A refusal three times running is the answer; once may be a blip.
        if (++refusals >= 3) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return null;
  }

  /// Requests paid after the app stopped waiting: each is asked about once
  /// more, and dropped once paid or a week old.
  static Future<void> resume() async {
    if (!allowed) return;
    final kept = await _kept();
    for (final entry in kept) {
      final ref = entry['ref'] as String;
      final at = DateTime.tryParse(entry['at'] as String? ?? '') ?? DateTime(2000);
      var done = DateTime.now().difference(at) > const Duration(days: 7);
      if (!done) {
        try {
          done = await _check(ref) != null;
        } catch (_) {
          // Refused or unreachable: asked again next time, until a week.
        }
      }
      if (done) await _drop(ref);
    }
  }

  /// The plan once paid, null while it hasn't landed; throws when the
  /// server refused it (short, someone else's, already used).
  static Future<String?> _check(String reference) async {
    Map<String, dynamic>? res;
    try {
      res = await GlyfApi.cryptoVerify(reference);
    } on GlyfApiException {
      rethrow;
    } catch (_) {
      // Offline for a moment: ask again.
    }
    if (res == null || res['ok'] != true) return null;
    final plan = res['plan'] as String? ?? 'free';
    await GlyfBridge.updateSharedSettings((s) {
      s['plan'] = plan;
      s['proUnlocked'] = plan != 'free';
      final pending = s['cryptoPending'];
      if (pending is List) s['cryptoPending'] = [for (final e in pending) if (e is Map && e['ref'] != reference) e];
      return s;
    });
    return plan;
  }

  static Future<List<Map<String, dynamic>>> _kept() async {
    final pending = (await GlyfBridge.sharedSettings())['cryptoPending'];
    return [
      if (pending is List)
        for (final e in pending)
          if (e is Map && e['ref'] is String) Map<String, dynamic>.from(e),
    ];
  }

  static Future<void> _keep(String reference) => GlyfBridge.updateSharedSettings((s) {
        final pending = s['cryptoPending'];
        final list = [
          if (pending is List)
            for (final e in pending)
              if (e is Map && e['ref'] != reference) e,
          {'ref': reference, 'at': DateTime.now().toIso8601String()},
        ];
        s['cryptoPending'] = list.length > 5 ? list.sublist(list.length - 5) : list;
        return s;
      });

  static Future<void> _drop(String reference) => GlyfBridge.updateSharedSettings((s) {
        final pending = s['cryptoPending'];
        if (pending is List) s['cryptoPending'] = [for (final e in pending) if (e is Map && e['ref'] != reference) e];
        return s;
      });

  static List<int> _u64(BigInt value) {
    final out = List<int>.filled(8, 0);
    var v = value;
    for (var i = 0; i < 8; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }
}
