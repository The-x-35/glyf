import 'dart:async';

import '../core/glyf_api.dart';
import 'evm_chains.dart';

/// EVM JSON-RPC through Glyf's server (POST /evm/rpc picks the chain's node
/// and allows only the calls a wallet makes).
abstract final class EvmRpc {
  static Future<Object?> call(EvmChain chain, String method, List<Object?> params) async {
    final res = await GlyfApi.evmPost('/evm/rpc', {'chain': chain.name, 'method': method, 'params': params});
    if (res['error'] != null) throw EvmRpcException(_message(res['error']));
    return res['result'];
  }

  static String _message(Object? error) =>
      error is Map ? (error['message'] as String? ?? 'The network refused') : '$error';

  static BigInt _big(Object? hex) {
    final s = (hex as String?) ?? '0x0';
    return BigInt.parse(s.startsWith('0x') ? s.substring(2) : s, radix: 16);
  }

  static Future<int> nonce(EvmChain chain, String address) async =>
      _big(await call(chain, 'eth_getTransactionCount', [address, 'pending'])).toInt();

  static Future<BigInt> balance(EvmChain chain, String address) async =>
      _big(await call(chain, 'eth_getBalance', [address, 'latest']));

  static Future<BigInt> estimateGas(EvmChain chain,
      {required String from, required String to, String? data, BigInt? value}) async {
    final tx = <String, Object?>{'from': from, 'to': to};
    if (data != null) tx['data'] = data;
    if (value != null && value > BigInt.zero) tx['value'] = '0x${value.toRadixString(16)}';
    return _big(await call(chain, 'eth_estimateGas', [tx]));
  }

  /// A tip and a cap: the tip the node suggests, and twice the next base fee
  /// on top of it, so a busy block or two doesn't strand the transaction.
  static Future<({BigInt maxFee, BigInt tip})> fees(EvmChain chain) async {
    final history = await call(chain, 'eth_feeHistory', ['0x5', 'latest', [50]]) as Map?;
    final bases = (history?['baseFeePerGas'] as List?) ?? const [];
    final base = bases.isEmpty ? BigInt.zero : _big(bases.last);
    BigInt tip;
    try {
      tip = _big(await call(chain, 'eth_maxPriorityFeePerGas', const []));
    } on EvmRpcException {
      tip = BigInt.from(1000000); // 0.001 gwei: an L2's usual floor
    }
    return (maxFee: base * BigInt.two + tip, tip: tip);
  }

  static Future<String> sendRaw(EvmChain chain, String raw) async =>
      (await call(chain, 'eth_sendRawTransaction', [raw])) as String;

  /// Waits for the transaction to land: true when it succeeded, false when
  /// it reverted, null when it's still out there after [timeout].
  static Future<Map<String, dynamic>?> receipt(EvmChain chain, String hash,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final r = await call(chain, 'eth_getTransactionReceipt', [hash]);
      if (r is Map) return Map<String, dynamic>.from(r);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  static bool succeeded(Map<String, dynamic> receipt) => receipt['status'] == '0x1';
}

class EvmRpcException implements Exception {
  EvmRpcException(this.message);
  final String message;
  @override
  String toString() => message;
}
