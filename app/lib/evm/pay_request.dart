import 'dart:convert';

import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;
import 'package:web3dart/web3dart.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_wallet.dart';

/// A USDT payment request on Whitechain (contracts/src/GlyfPayRequest.sol):
/// someone asks in a chat, the other side opens the link and pays it, and
/// the contract keeps the receipt both can check. The link carries only the
/// chain, the contract and the id; everything shown is read from the chain.
class PayRequest {
  const PayRequest({
    required this.id,
    required this.token,
    required this.payee,
    required this.payer,
    required this.units,
    required this.memo,
    required this.status,
    required this.expiresAt,
    this.paidBy,
  });

  final BigInt id;
  final String token;
  final String payee;

  /// The named payer, or null for anyone.
  final String? payer;
  final BigInt units;
  final String memo;
  final PayRequestStatus status;
  final DateTime? expiresAt;
  final String? paidBy;

  /// Whole USDT, as people say it.
  String get amount => PayRequests.whole(units);

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

enum PayRequestStatus { none, open, paid, cancelled, refunded }

abstract final class PayRequests {
  static EvmChain get chain => EvmChain.whitechainSepolia;

  /// Whitechain's test USDT (the prize's own token), 6 decimals.
  static const usdt = '0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7';
  static const usdtDecimals = 6;

  /// GlyfPayRequest on Whitechain Sepolia (contracts/deployments/
  /// whitechain-sepolia.json once deployed); `payRequestContract` in shared
  /// settings overrides it for a test chain.
  static const deployed = String.fromEnvironment('GLYF_PAY_REQUEST', defaultValue: '');

  static Future<String> contract() async {
    final s = await GlyfBridge.sharedSettings();
    final override = s['payRequestContract'] as String?;
    final c = (override != null && override.isNotEmpty) ? override : deployed;
    if (c.isEmpty) throw GlyfApiException('Requests open once GlyfPayRequest is on Whitechain');
    return c;
  }

  static final _abi = ContractAbi.fromJson(_abiJson, 'GlyfPayRequest');
  static ContractFunction _fn(String name) => _abi.functions.firstWhere((f) => f.name == name);

  static String link(String contract, BigInt id) =>
      'https://www.tryglyf.com/pay?chain=${chain.id}&contract=$contract&id=$id';

  /// The link's id and contract, if it's one of ours (glyf://pay-request or
  /// the https form).
  static ({String contract, BigInt id})? parse(Uri uri) {
    final q = uri.queryParameters;
    final id = BigInt.tryParse(q['id'] ?? '');
    final c = q['contract'];
    if (id == null || c == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(c)) return null;
    if (q['chain'] != null && q['chain'] != '${chain.id}') return null;
    return (contract: c, id: id);
  }

  static BigInt units(String amount) {
    final parts = amount.split('.');
    final frac = (parts.length > 1 ? parts[1] : '').padRight(usdtDecimals, '0').substring(0, usdtDecimals);
    return BigInt.parse(parts[0].isEmpty ? '0' : parts[0]) * BigInt.from(10).pow(usdtDecimals) + BigInt.parse(frac);
  }

  static String whole(BigInt units) {
    final scale = BigInt.from(10).pow(usdtDecimals);
    final frac = (units % scale).toString().padLeft(usdtDecimals, '0').replaceFirst(RegExp(r'0+$'), '');
    return frac.isEmpty ? '${units ~/ scale}' : '${units ~/ scale}.$frac';
  }

  /// Asks for [amount] USDT from anyone, never expiring; resolves with the
  /// new request's id, the transaction and its link.
  static Future<({BigInt id, String txHash, String link})> create({required String amount, String memo = ''}) async {
    final c = await contract();
    final address = await EvmWallet.load();
    if (address == null) throw GlyfApiException('No Glyf wallet yet');
    final data = _fn('createRequest').encodeCall([
      EthereumAddress.fromHex(usdt),
      units(amount),
      memo.length > 140 ? memo.substring(0, 140) : memo,
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
      BigInt.zero,
    ]);
    final hash = await EvmWallet.send(chain, EvmCall(to: c, data: '0x${bytesToHex(data)}'));
    final receipt = await EvmRpc.receipt(chain, hash);
    if (receipt == null) throw GlyfApiException('Whitechain is taking long to confirm the request');
    if (!EvmRpc.succeeded(receipt)) throw GlyfApiException('Whitechain refused the request');
    for (final log in (receipt['logs'] as List? ?? const []).cast<Map>()) {
      final topics = (log['topics'] as List?)?.cast<String>() ?? const [];
      if (topics.length > 1 && topics[0] == _requestCreated) {
        final id = BigInt.parse(topics[1].substring(2), radix: 16);
        return (id: id, txHash: hash, link: link(c, id));
      }
    }
    throw GlyfApiException('The request was made but its id wasn’t in the receipt');
  }

  static Future<PayRequest> load(String contract, BigInt id) async {
    final fn = _fn('getRequest');
    final raw = await EvmRpc.call(chain, 'eth_call', [
      {'to': contract, 'data': '0x${bytesToHex(fn.encodeCall([id]))}'},
      'latest',
    ]) as String;
    final tuple = fn.decodeReturnValues(raw).first as List;
    String? address(Object v) {
      final a = (v as EthereumAddress).hexEip55;
      return a == '0x0000000000000000000000000000000000000000' ? null : a;
    }
    final expires = (tuple[1] as BigInt).toInt();
    return PayRequest(
      id: id,
      token: (tuple[0] as EthereumAddress).hexEip55,
      expiresAt: expires == 0 ? null : DateTime.fromMillisecondsSinceEpoch(expires * 1000),
      status: PayRequestStatus.values[(tuple[2] as BigInt).toInt().clamp(0, 4)],
      payee: (tuple[3] as EthereumAddress).hexEip55,
      payer: address(tuple[5]),
      paidBy: address(tuple[7]),
      units: tuple[8] as BigInt,
      memo: tuple[10] as String,
    );
  }

  /// Pays [request] from the Glyf wallet: an allowance for exactly the
  /// amount when the contract hasn't one, then pay. Resolves with the pay
  /// transaction's hash once it has landed.
  static Future<String> pay(String contract, PayRequest request) async {
    final me = await EvmWallet.load();
    if (me == null) throw GlyfApiException('No Glyf wallet yet');
    final allowance = await _uint(request.token,
        '0xdd62ed3e${_word(me.substring(2))}${_word(contract.substring(2))}');
    if (allowance < request.units) {
      final approve = '0x095ea7b3${_word(contract.substring(2))}${_word(request.units.toRadixString(16))}';
      final hash = await EvmWallet.send(chain, EvmCall(to: request.token, data: approve));
      final r = await EvmRpc.receipt(chain, hash);
      if (r == null || !EvmRpc.succeeded(r)) throw GlyfApiException('The USDT allowance didn’t go through');
    }
    final data = _fn('pay').encodeCall([request.id]);
    final hash = await EvmWallet.send(chain, EvmCall(to: contract, data: '0x${bytesToHex(data)}'));
    final r = await EvmRpc.receipt(chain, hash);
    if (r == null) throw GlyfApiException('Whitechain is taking long to confirm the payment');
    if (!EvmRpc.succeeded(r)) throw GlyfApiException('Whitechain refused the payment');
    return hash;
  }

  /// The USDT the Glyf wallet holds on Whitechain, whole.
  static Future<String> balance() async {
    final me = await EvmWallet.load();
    if (me == null) return '0';
    return whole(await _uint(usdt, '0x70a08231${_word(me.substring(2))}'));
  }

  static Future<BigInt> _uint(String to, String data) async {
    final raw = await EvmRpc.call(chain, 'eth_call', [
      {'to': to, 'data': data},
      'latest',
    ]) as String;
    final hex = raw.length > 2 ? raw.substring(2) : '0';
    return BigInt.parse(hex.isEmpty ? '0' : hex, radix: 16);
  }

  static String _word(String hex) => hex.toLowerCase().padLeft(64, '0');

  static const _requestCreated = '0xd988cc93adff19f054abec3efa515e5ea9b6f67c969949885793ca43d89639b3';

  /// The functions the app calls (contracts/abi/GlyfPayRequest.json).
  static final _abiJson = jsonEncode([
    {
      'inputs': [
        {'name': 'token', 'type': 'address'},
        {'name': 'amount', 'type': 'uint256'},
        {'name': 'memo', 'type': 'string'},
        {'name': 'payer', 'type': 'address'},
        {'name': 'expiresAt', 'type': 'uint64'},
      ],
      'name': 'createRequest',
      'outputs': [
        {'name': 'requestId', 'type': 'uint256'},
      ],
      'stateMutability': 'nonpayable',
      'type': 'function',
    },
    {
      'inputs': [
        {'name': 'requestId', 'type': 'uint256'},
      ],
      'name': 'pay',
      'outputs': <Object>[],
      'stateMutability': 'nonpayable',
      'type': 'function',
    },
    {
      'inputs': [
        {'name': 'requestId', 'type': 'uint256'},
      ],
      'name': 'getRequest',
      'outputs': [
        {
          'components': [
            {'name': 'token', 'type': 'address'},
            {'name': 'expiresAt', 'type': 'uint64'},
            {'name': 'status', 'type': 'uint8'},
            {'name': 'payee', 'type': 'address'},
            {'name': 'createdAt', 'type': 'uint64'},
            {'name': 'payer', 'type': 'address'},
            {'name': 'paidAt', 'type': 'uint64'},
            {'name': 'paidBy', 'type': 'address'},
            {'name': 'amount', 'type': 'uint256'},
            {'name': 'refunded', 'type': 'uint256'},
            {'name': 'memo', 'type': 'string'},
          ],
          'name': '',
          'type': 'tuple',
        },
      ],
      'stateMutability': 'view',
      'type': 'function',
    },
  ]);

  /// For tests: the calldata of createRequest.
  static String createCalldata(String amount, String memo) => '0x${bytesToHex(_fn('createRequest').encodeCall([
        EthereumAddress.fromHex(usdt),
        units(amount),
        memo,
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
        BigInt.zero,
      ]))}';

  /// For tests: a getRequest answer read back.
  static List<dynamic> decodeRequest(String raw) => _fn('getRequest').decodeReturnValues(raw);

  static List<int> hex(String s) => hexToBytes(s);
}
