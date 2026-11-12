import '../core/glyf_api.dart';

/// One side of a NEAR Intents quote: the coin, the Glyf chain it is on, and
/// its contract (null for a chain's own coin).
class NearAsset {
  const NearAsset({required this.symbol, required this.chain, required this.decimals, this.address});

  final String symbol;
  final String chain;
  final int decimals;
  final String? address;

  static NearAsset fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return NearAsset(
      symbol: '${m['symbol'] ?? ''}',
      chain: '${m['chain'] ?? ''}',
      decimals: (m['decimals'] as num?)?.toInt() ?? 0,
      address: m['address'] as String?,
    );
  }
}

/// How the deposit is made (docs/NEAR-SPEC.md, POST /near/quote `deposit`):
/// `erc20`, `native` (EVM, signed in MetaMask), `sol`, `spl` (Solana,
/// signed in Phantom), `near` (NEAR, signed in HOT Wallet) or `manual`
/// (any other chain: shown to copy).
class NearDeposit {
  const NearDeposit({
    required this.kind,
    required this.chain,
    this.chainId,
    this.to,
    this.data,
    this.value,
    this.amountBase,
    this.token,
    this.depositAddress,
    this.lamports,
    this.mint,
    this.decimals,
    this.receiverId,
  });

  final String kind;
  final String chain;
  final int? chainId;
  final String? to;
  final String? data;
  final String? value;
  final String? amountBase;
  final String? token;
  final String? depositAddress;
  final String? lamports;
  final String? mint;
  final int? decimals;

  /// `near`: the token contract the transaction goes to.
  final String? receiverId;

  static NearDeposit fromJson(Object? j) {
    final m = j is Map ? j : const {};
    String? s(String k) => m[k] == null ? null : '${m[k]}';
    return NearDeposit(
      kind: s('kind') ?? 'manual',
      chain: s('chain') ?? '',
      chainId: (m['chainId'] as num?)?.toInt(),
      to: s('to'),
      data: s('data'),
      value: s('value'),
      amountBase: s('amountBase'),
      token: s('token'),
      depositAddress: s('depositAddress'),
      lamports: s('lamports'),
      mint: s('mint'),
      decimals: (m['decimals'] as num?)?.toInt(),
      receiverId: s('receiverId'),
    );
  }
}

/// One Guard check on the recipient (server lib/nearguard.ts).
class NearCheck {
  const NearCheck(this.id, this.level, this.text);
  final String id;

  /// `warn` or `block`.
  final String level;
  final String text;
}

/// POST /near/quote's answer.
class NearQuote {
  const NearQuote({
    required this.dry,
    required this.sell,
    required this.buy,
    required this.amountIn,
    required this.amountOut,
    this.amountInBase,
    this.amountInUsd,
    this.amountOutUsd,
    this.minAmountOut,
    this.timeSeconds,
    this.depositAddress,
    this.depositMemo,
    this.deadline,
    this.deposit,
    this.explorer,
    this.guardLevel = 'ok',
    this.checks = const [],
  });

  final bool dry;
  final NearAsset sell;
  final NearAsset buy;
  final String amountIn;
  final String? amountInBase;
  final String? amountInUsd;
  final String amountOut;
  final String? amountOutUsd;
  final String? minAmountOut;
  final int? timeSeconds;
  final String? depositAddress;
  final String? depositMemo;
  final DateTime? deadline;
  final NearDeposit? deposit;
  final String? explorer;

  /// `ok`, `warn` or `block`: the worst of [checks].
  final String guardLevel;
  final List<NearCheck> checks;

  bool get blocked => guardLevel == 'block' || checks.any((c) => c.level == 'block');

  static NearQuote fromJson(Map<String, dynamic> j) {
    final guard = j['guard'] is Map ? j['guard'] as Map : const {};
    String? s(String k) => j[k] == null ? null : '${j[k]}';
    return NearQuote(
      dry: j['dry'] == true,
      sell: NearAsset.fromJson(j['sell']),
      buy: NearAsset.fromJson(j['buy']),
      amountIn: s('amountIn') ?? '',
      amountInBase: s('amountInBase'),
      amountInUsd: s('amountInUsd'),
      amountOut: s('amountOut') ?? '',
      amountOutUsd: s('amountOutUsd'),
      minAmountOut: s('minAmountOut'),
      timeSeconds: (j['timeSeconds'] as num?)?.toInt(),
      depositAddress: s('depositAddress'),
      depositMemo: s('depositMemo'),
      deadline: DateTime.tryParse(s('deadline') ?? ''),
      deposit: j['deposit'] is Map ? NearDeposit.fromJson(j['deposit']) : null,
      explorer: s('explorer'),
      guardLevel: '${guard['level'] ?? 'ok'}',
      checks: [
        for (final c in (guard['checks'] as List? ?? const []).whereType<Map>())
          NearCheck('${c['id'] ?? ''}', '${c['level'] ?? 'warn'}', '${c['text'] ?? ''}'),
      ],
    );
  }
}

/// A link to a transaction on its own chain's explorer.
typedef NearTx = ({String hash, String? url});

/// GET /near/status's answer: PENDING_DEPOSIT, INCOMPLETE_DEPOSIT,
/// PROCESSING, SUCCESS, REFUNDED or FAILED.
class NearStatus {
  const NearStatus({required this.status, this.done = false, this.amountOut, this.destinationTx, this.originTx, this.explorer});

  final String status;
  final bool done;
  final String? amountOut;
  final NearTx? destinationTx;
  final NearTx? originTx;
  final String? explorer;

  static NearTx? _tx(Object? j) =>
      j is Map && j['hash'] != null ? (hash: '${j['hash']}', url: j['url'] as String?) : null;

  static NearStatus fromJson(Map<String, dynamic> j) => NearStatus(
        status: '${j['status'] ?? 'PENDING_DEPOSIT'}'.toUpperCase(),
        done: j['done'] == true,
        amountOut: j['amountOut'] == null ? null : '${j['amountOut']}',
        destinationTx: _tx(j['destinationTx']),
        originTx: _tx(j['originTx']),
        explorer: j['explorer'] as String?,
      );
}

/// Glyf's server routes for NEAR Intents (server/src/routes/near.ts): it
/// speaks to 1Click, the app only to it. A test stands in for the server by
/// overriding these.
class NearApi {
  const NearApi();

  /// POST /near/quote; a refusal comes back as a GlyfApiException in the
  /// server's plain words ("Too small for NEAR Intents: at least $1").
  Future<NearQuote> quote(Map<String, Object?> body) async {
    final res = await GlyfApi.evmPost('/near/quote', body, timeout: const Duration(seconds: 30));
    if (res['ok'] == false) throw GlyfApiException('${res['error'] ?? 'NEAR Intents had no quote'}');
    return NearQuote.fromJson(res);
  }

  /// POST /near/submit: tells 1Click the deposit went out, which speeds up
  /// its pickup.
  /// [nearSender]: the account that paid a deposit on NEAR.
  Future<void> submit({required String depositAddress, required String txHash, String? memo, String? nearSender}) =>
      GlyfApi.evmPost('/near/submit',
          {'depositAddress': depositAddress, 'txHash': txHash, 'memo': ?memo, 'nearSenderAccount': ?nearSender});

  /// GET /near/status for the deposit address.
  Future<NearStatus> status({required String depositAddress, String? memo}) async {
    final query = 'deposit=${Uri.encodeQueryComponent(depositAddress)}'
        '${memo == null ? '' : '&memo=${Uri.encodeQueryComponent(memo)}'}';
    return NearStatus.fromJson(await GlyfApi.evmGet('/near/status?$query'));
  }
}
