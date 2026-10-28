import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/glyf_api.dart';
import 'solana.dart';

/// Something a person can act on, never a stack trace.
class WalletError implements Exception {
  const WalletError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A token as Jupiter knows it.
class TokenInfo {
  const TokenInfo({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.usdPrice,
    this.icon,
    this.verified = false,
    this.stock = false,
  });

  final String mint;
  final String symbol;
  final String name;
  final int decimals;
  final double? usdPrice;
  final String? icon;
  final bool verified;

  /// A tokenized stock (xStocks, Ondo), by Jupiter's tags.
  final bool stock;

  static TokenInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final mint = json['id'], symbol = json['symbol'], decimals = json['decimals'];
    if (mint is! String || symbol is! String || decimals is! num) return null;
    return TokenInfo(
      mint: mint,
      symbol: symbol,
      // Jupiter calls SOL "Wrapped SOL"; a buy lands as plain SOL.
      name: mint == Sol.wsol ? 'Solana' : json['name'] as String? ?? symbol,
      decimals: decimals.toInt(),
      usdPrice: (json['usdPrice'] as num?)?.toDouble(),
      icon: json['icon'] as String?,
      verified: json['isVerified'] == true,
      stock: json['tags'] is List &&
          (json['tags'] as List).any((t) => t == 'stocks' || t == 'equities' || t == 'xstocks'),
    );
  }

  static const sol = TokenInfo(
    mint: Sol.wsol,
    symbol: 'SOL',
    name: 'Solana',
    decimals: Sol.solDecimals,
    verified: true,
  );
  static const usdc = TokenInfo(
    mint: Sol.usdc,
    symbol: 'USDC',
    name: 'USD Coin',
    decimals: Sol.usdcDecimals,
    usdPrice: 1,
    verified: true,
  );
}

/// A swap Jupiter has priced, and built when it was given a taker.
class JupiterOrder {
  const JupiterOrder({
    required this.requestId,
    required this.inAmount,
    required this.outAmount,
    this.transaction,
    this.priceImpact,
    this.inUsd,
    this.outUsd,
    this.glyfFeeBps,
  });

  final String requestId;
  final BigInt inAmount;

  /// Net of every fee, Glyf's included: Jupiter takes the fee before it
  /// quotes (measured 2026-10-14, docs/SWAP-FEE.md).
  final BigInt outAmount;

  /// Glyf's fee on this swap, when Jupiter applied the referral; null
  /// without one.
  final int? glyfFeeBps;

  /// Base64, unsigned; null for a price-only quote.
  final String? transaction;
  final double? priceImpact;
  final double? inUsd;
  final double? outUsd;
}

Future<Object?> _http(String method, Uri url, {Object? body, Duration timeout = const Duration(seconds: 15)}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = method == 'GET' ? await client.getUrl(url) : await client.postUrl(url);
    req.headers.set('accept', 'application/json');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join();
    final json = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final error = json is Map ? (json['error'] ?? json['errorMessage'] ?? json['message']) : null;
      final message = error is Map ? error['message'] : error;
      throw WalletError(message is String && message.isNotEmpty ? message : 'Something went wrong (${res.statusCode})');
    }
    return json;
  } on WalletError {
    rethrow;
  } on TimeoutException {
    throw const WalletError('No answer in time. Try again');
  } on SocketException {
    throw const WalletError('You look offline. Try again');
  } finally {
    client.close();
  }
}

/// Glyf's fee on a buy: Jupiter's referral fee on Swap V2 /order
/// (docs/SWAP-FEE.md). Off while [referralAccount] is empty, and then a buy
/// is exactly what it was without it. Twins: SwapFee in
/// GlyfKeyboard/Engine/TokenLookup.swift and ime/SwapFee.kt.
abstract final class SwapFee {
  /// The referral account made at referral.jup.ag under Jupiter's Ultra
  /// referral project. Public, not a secret.
  static const referralAccount = '';

  /// 0.5%. Jupiter takes 50 to 255 and keeps a fifth of it.
  static const bps = 50;

  /// What /order is given on top of the swap itself.
  static Map<String, String> params([String account = referralAccount]) =>
      account.isEmpty ? const {} : {'referralAccount': account, 'referralFee': '$bps'};

  /// "Fee 0.5%".
  static String label(int bps) {
    var pct = (bps / 100).toStringAsFixed(2);
    pct = pct.replaceFirst(RegExp(r'\.?0+$'), '');
    return 'Fee $pct%';
  }

  /// The fee Jupiter says it applied for Glyf, from an /order answer.
  static int? applied(Map<String, dynamic> json) {
    final account = json['referralAccount'];
    if (account is! String || account.isEmpty) return null;
    return (json['feeBps'] as num?)?.toInt() ?? bps;
  }
}

/// Jupiter, straight from the phone and without a key (about 30 calls a
/// minute per phone, plenty for one person): tokens, prices and swaps
/// (Swap API V2: /order builds the transaction, /execute lands it).
abstract final class Jupiter {
  static const _base = 'https://api.jup.ag';

  /// A token by its contract address, or by ticker ("BONK", "sol"). An
  /// address Jupiter doesn't list is a wallet, or a token nobody trades.
  static Future<TokenInfo?> token(String query) async {
    final q = query.trim().replaceFirst(RegExp(r'^\$'), '');
    if (q.isEmpty) return null;
    final json = await _http('GET', Uri.parse('$_base/tokens/v2/search').replace(queryParameters: {'query': q}));
    final found = [for (final t in (json as List? ?? const [])) ?TokenInfo.fromJson(t)];
    if (found.isEmpty) return null;
    if (Sol.isAddress(q)) {
      for (final t in found) {
        if (t.mint == q) return t;
      }
      return null;
    }
    final upper = q.toUpperCase();
    final exact = found.where((t) => t.symbol.toUpperCase() == upper).toList();
    // Verified first: a ticker is claimed by many tokens, most of them copies.
    exact.sort((a, b) => (b.verified ? 1 : 0) - (a.verified ? 1 : 0));
    return exact.isNotEmpty ? exact.first : null;
  }

  /// The /order link: the swap, the taker when building, Glyf's fee when
  /// a referral account is set.
  static Uri orderUri({
    required String inputMint,
    required String outputMint,
    required BigInt amount,
    String? taker,
    String referral = SwapFee.referralAccount,
  }) => Uri.parse('$_base/swap/v2/order').replace(
    queryParameters: {
      'inputMint': inputMint,
      'outputMint': outputMint,
      'amount': amount.toString(),
      'taker': ?taker,
      ...SwapFee.params(referral),
    },
  );

  static Future<JupiterOrder> order({
    required String inputMint,
    required String outputMint,
    required BigInt amount,
    String? taker,
  }) async {
    Map<String, dynamic> json;
    try {
      json =
          await _http('GET', orderUri(inputMint: inputMint, outputMint: outputMint, amount: amount, taker: taker))
              as Map<String, dynamic>;
    } on WalletError catch (e) {
      // A referral account Jupiter refuses (not made yet, wrong project)
      // must cost Glyf its fee, never the person their buy.
      if (SwapFee.referralAccount.isEmpty || !e.message.toLowerCase().contains('referral')) rethrow;
      json =
          await _http(
                'GET',
                orderUri(inputMint: inputMint, outputMint: outputMint, amount: amount, taker: taker, referral: ''),
              )
              as Map<String, dynamic>;
    }
    final code = json['errorCode'];
    if (code != null && (json['transaction'] as String? ?? '').isEmpty && taker != null) {
      throw WalletError(switch (code) {
        1 => 'Not enough in your wallet for that',
        2 => 'Not enough SOL for the network fee',
        _ => json['errorMessage'] as String? ?? 'Jupiter can’t make that swap right now',
      });
    }
    final requestId = json['requestId'] as String?;
    final outAmount = BigInt.tryParse('${json['outAmount'] ?? ''}');
    if (requestId == null || outAmount == null) {
      throw WalletError(json['errorMessage'] as String? ?? 'Jupiter can’t price that right now');
    }
    final tx = json['transaction'] as String?;
    return JupiterOrder(
      requestId: requestId,
      inAmount: BigInt.tryParse('${json['inAmount']}') ?? amount,
      outAmount: outAmount,
      transaction: tx == null || tx.isEmpty ? null : tx,
      priceImpact: double.tryParse('${json['priceImpact']}'),
      inUsd: (json['inUsdValue'] as num?)?.toDouble(),
      outUsd: (json['outUsdValue'] as num?)?.toDouble(),
      glyfFeeBps: SwapFee.applied(json),
    );
  }

  /// Lands a swap Phantom signed. The signature, or why it failed.
  static Future<String> execute(Uint8List signed, String requestId) async {
    final json =
        await _http(
              'POST',
              Uri.parse('$_base/swap/v2/execute'),
              body: {'signedTransaction': base64.encode(signed), 'requestId': requestId},
              timeout: const Duration(seconds: 40),
            )
            as Map<String, dynamic>;
    final signature = json['signature'] as String?;
    if (json['status'] == 'Success' && signature != null) return signature;
    final code = json['code'];
    throw WalletError(switch (code) {
      -1 || -1004 || -2003 => 'That price expired. Try again',
      _ => json['error'] as String? ?? 'The swap didn’t go through',
    });
  }
}

/// Glyf's fee on a private payment (Arpit, 2026-10-28: "take 0.1% fees").
/// The server names the wallet that receives it (GET /wallet/fees), the
/// phone adds the transfer in front of MagicBlock's own instructions, and
/// the person signs both at once. Every Glyf private payment then carries
/// that one Glyf address, which is how MagicBlock counts Glyf's usage. No
/// wallet configured, or the server unreachable: no fee, the payment goes
/// through exactly as before.
abstract final class PrivateFee {
  static ({String? wallet, int bps})? _cached;

  /// The fee wallet and rate, asked once per launch.
  static Future<({String? wallet, int bps})> config() async {
    final hit = _cached;
    if (hit != null) return hit;
    try {
      final json = await GlyfApi.walletFees();
      final wallet = json['feeWallet'];
      final bps = (json['privateFeeBps'] as num?)?.toInt() ?? 0;
      final ok = wallet is String && Sol.isAddress(wallet) && bps > 0 && bps <= 100;
      return _cached = (wallet: ok ? wallet : null, bps: ok ? bps : 0);
    } catch (_) {
      return (wallet: null, bps: 0);
    }
  }

  /// [units] times [bps] / 10 000, rounded down (nothing on dust).
  static BigInt amountFor(BigInt units, int bps) => units * BigInt.from(bps) ~/ BigInt.from(10000);

  /// "0.1%".
  static String percent(int bps) {
    var pct = (bps / 100).toStringAsFixed(2);
    return pct.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// MagicBlock's private payments (docs.magicblock.gg, ephemeral SPL token):
/// one transaction the sender signs, paid out to the recipient's normal
/// account through the hardware-secured (TEE) validator, so the link
/// between the two isn't left on chain. No key needed.
abstract final class MagicBlock {
  static const _base = 'https://payments.magicblock.app';

  /// Unsigned, legacy (Phantom's deeplinks document legacy transactions).
  static Future<Uint8List> privateTransfer({
    required String from,
    required String to,
    required BigInt amount,
    String mint = Sol.usdc,
  }) async {
    final json =
        await _http(
              'POST',
              Uri.parse('$_base/v1/spl/transfer'),
              body: {
                'from': from,
                'to': to,
                'mint': mint,
                'amount': amount.toInt(),
                'visibility': 'private',
                'fromBalance': 'base',
                'toBalance': 'base',
                'cluster': 'mainnet-private',
                'initAtasIfMissing': true,
                'legacy': true,
              },
            )
            as Map<String, dynamic>;
    final tx = json['transactionBase64'] as String?;
    if (tx == null) throw const WalletError('MagicBlock couldn’t build that payment');
    return base64.decode(tx);
  }

  /// Sends a signed private payment to Solana. The signature.
  static Future<String> send(Uint8List signed) async {
    final json =
        await _http(
              'POST',
              Uri.parse('$_base/v1/transaction/send'),
              body: {'transactionBase64': base64.encode(signed), 'sendTo': 'base', 'cluster': 'mainnet-private'},
              timeout: const Duration(seconds: 40),
            )
            as Map<String, dynamic>;
    final signature = json['signature'] as String?;
    if (signature == null) throw const WalletError('The payment didn’t go through');
    return signature;
  }
}

/// Solana through Glyf's server (POST /wallet/rpc adds the node's key).
abstract final class SolanaRpc {
  static Future<Object?> _call(String method, List<Object?> params) async {
    try {
      return await GlyfApi.walletRpc(method, params);
    } on GlyfApiException catch (e) {
      throw WalletError(_plain(e.message));
    } on TimeoutException {
      throw const WalletError('Solana didn’t answer. Try again');
    } on SocketException {
      throw const WalletError('You look offline. Try again');
    }
  }

  /// The node's words, as something to do.
  static String _plain(String message) {
    final m = message.toLowerCase();
    if (m.contains('no record of a prior credit')) return 'Your wallet needs a little SOL for the network fee';
    if (m.contains('insufficient') || m.contains('0x1')) return 'Not enough in your wallet for that and the fee';
    if (m.contains('blockhash')) return 'That took too long. Try again';
    if (m.contains('simulation failed') || m.contains('custom program error')) {
      return 'Solana turned it down. Nothing was sent';
    }
    return message;
  }

  static Future<String> blockhash() async {
    final json =
        await _call('getLatestBlockhash', [
              {'commitment': 'confirmed'},
            ])
            as Map?;
    final hash = (json?['value'] as Map?)?['blockhash'];
    if (hash is! String) throw const WalletError('Solana didn’t answer. Try again');
    return hash;
  }

  static Future<BigInt> solBalance(String owner) async {
    final json =
        await _call('getBalance', [
              owner,
              {'commitment': 'confirmed'},
            ])
            as Map?;
    return BigInt.from((json?['value'] as num?) ?? 0);
  }

  /// The program that owns [address], or null when nothing lives there yet
  /// (a wallet that was never paid). A wallet is owned by the System
  /// Program; a token, a token account or an app is not.
  static Future<String?> owner(String address) async {
    final json =
        await _call('getAccountInfo', [
              address,
              {
                'encoding': 'base64',
                'commitment': 'confirmed',
                'dataSlice': {'offset': 0, 'length': 0},
              },
            ])
            as Map?;
    return (json?['value'] as Map?)?['owner'] as String?;
  }

  /// All of [owner]'s [mint], in base units.
  static Future<BigInt> tokenBalance(String owner, String mint) async {
    final json =
        await _call('getTokenAccountsByOwner', [
              owner,
              {'mint': mint},
              {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
            ])
            as Map?;
    var total = BigInt.zero;
    for (final account in (json?['value'] as List? ?? const [])) {
      final amount =
          (((((account as Map)['account'] as Map?)?['data'] as Map?)?['parsed'] as Map?)?['info']
                  as Map?)?['tokenAmount']
              as Map?;
      total += BigInt.tryParse('${amount?['amount'] ?? 0}') ?? BigInt.zero;
    }
    return total;
  }

  /// Sends a transaction Phantom signed. The signature.
  static Future<String> send(Uint8List signed) async {
    final signature = await _call('sendTransaction', [
      base64.encode(signed),
      {'encoding': 'base64', 'preflightCommitment': 'confirmed', 'maxRetries': 5},
    ]);
    if (signature is! String) throw const WalletError('The payment didn’t go through');
    return signature;
  }

  /// Waits until Solana confirms [signature]: true, false if it failed,
  /// null if it's still pending after [wait].
  static Future<bool?> confirm(String signature, {Duration wait = const Duration(seconds: 30)}) async {
    final until = DateTime.now().add(wait);
    while (DateTime.now().isBefore(until)) {
      final json =
          await _call('getSignatureStatuses', [
                [signature],
                {'searchTransactionHistory': false},
              ])
              as Map?;
      final status = (json?['value'] as List?)?.first as Map?;
      if (status != null) {
        if (status['err'] != null) return false;
        final level = status['confirmationStatus'];
        if (level == 'confirmed' || level == 'finalized') return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return null;
  }
}
