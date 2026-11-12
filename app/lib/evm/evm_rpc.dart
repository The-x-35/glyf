import 'dart:async';

import '../core/glyf_api.dart';
import 'evm_chains.dart';

/// EVM JSON-RPC through Glyf's server (POST /evm/rpc picks the chain's node
/// and carries reads only: nothing that signs or sends).
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

  static Future<BigInt> balance(EvmChain chain, String address) async =>
      _big(await call(chain, 'eth_getBalance', [address, 'latest']));

  /// Waits for a transaction the wallet app sent to land: its receipt, or
  /// null when it's still out there after [timeout]. Glyf only reads here:
  /// MetaMask builds, signs and sends.
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
