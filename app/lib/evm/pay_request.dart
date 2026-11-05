import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_wallet.dart';

/// A USDT payment request on Whitechain (contracts/src/GlyfPayRequest.sol):
/// someone asks in a chat, the other side opens the link and pays it, and
/// the contract keeps the receipt both can check.
class PayRequest {
  const PayRequest({
    required this.id,
    required this.payee,
    required this.amount,
    required this.memo,
    required this.status,
  });

  final BigInt id;
  final String payee;

  /// Whole USDT.
  final String amount;
  final String memo;

  /// open, paid, cancelled, expired.
  final String status;
}

abstract final class PayRequests {
  static EvmChain get chain => EvmChain.whitechainSepolia;

  /// Whitechain's test USDT (the prize's own token).
  static const usdt = '0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7';
  static const usdtDecimals = 6;

  /// GlyfPayRequest on Whitechain Sepolia, once deployed (contracts/README.md).
  static String contract = const String.fromEnvironment('GLYF_PAY_REQUEST', defaultValue: '');

  static String link(BigInt id) =>
      'https://www.tryglyf.com/pay?chain=${chain.id}&contract=$contract&id=$id';

  static Future<({BigInt id, String txHash, String link})> create({required String amount, String memo = ''}) async {
    if (contract.isEmpty) throw GlyfApiException('Requests open once GlyfPayRequest is on Whitechain');
    throw GlyfApiException('Requests are being wired to the deployed contract');
  }

  static Future<PayRequest> load(BigInt id) async {
    if (contract.isEmpty) throw GlyfApiException('Requests open once GlyfPayRequest is on Whitechain');
    throw GlyfApiException('Requests are being wired to the deployed contract');
  }

  static Future<String> pay(PayRequest request) async {
    await EvmWallet.load();
    await EvmRpc.nonce(chain, request.payee);
    throw GlyfApiException('Requests are being wired to the deployed contract');
  }
}
