import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_wallet.dart';
import 'package:glyf/evm/trade_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, String> secrets;
  late Map<String, dynamic> shared;

  setUp(() {
    secrets = {};
    shared = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'walletSecretLoad':
          return secrets[args['name']];
        case 'walletSecretSave':
          secrets[args['name'] as String] = args['value'] as String;
          return true;
        case 'walletSecretClear':
          secrets.remove(args['name']);
          return true;
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    await EvmWallet.forget();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  test('the wallet is made once, kept in the Keychain and shared with the keyboard', () async {
    expect(await EvmWallet.load(), isNull);
    final address = await EvmWallet.ensure();
    expect(address, matches(RegExp(r'^0x[0-9a-fA-F]{40}$')));
    expect(secrets['evm-key'], hasLength(64));
    expect(shared['evmAddress'], address);
    // The same key comes back, not a new one.
    expect(await EvmWallet.ensure(), address);
  });

  test('typed data is signed by the wallet’s own key (Flash orders)', () async {
    final address = await EvmWallet.ensure();
    final typed = {
      'types': {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
        ],
        'Order': [
          {'name': 'qty', 'type': 'uint256'},
          {'name': 'owner', 'type': 'address'},
        ],
      },
      'primaryType': 'Order',
      'domain': {'name': 'Flash', 'chainId': 8453},
      'message': {'qty': '50000000', 'owner': address},
    };
    final signature = EvmWallet.signTypedData(typed);
    final signer = EthSigUtil.recoverSignature(
      signature: signature,
      message: TypedDataUtil.hashMessage(jsonData: jsonEncode(typed), version: TypedDataVersion.V4),
    );
    expect(signer.toLowerCase(), address.toLowerCase());
  });

  test('an ERC-20 transfer is the transfer selector, the address and the amount', () {
    final data = TradeFlow.erc20Transfer('0x52908400098527886E0F7030069857D2E4169EE7', BigInt.from(20000000));
    expect(data.substring(0, 10), '0xa9059cbb');
    expect(data.length, 10 + 128);
    expect(data, endsWith('1312d00'));
    expect(data.substring(10, 74), '00000000000000000000000052908400098527886e0f7030069857d2e4169ee7');
  });

  test('the keyboard’s words become Flash’s order body', () async {
    final address = await EvmWallet.ensure();
    final stop = await TradeFlow.flashBody(
        {'kind': 'stop-loss', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.2', 'price': '3000', 'chain': 'base'},
        'stop-loss', EvmChain.base, address);
    expect(stop['orderType'], 'stop-loss');
    expect(stop['side'], 'sell');
    expect(stop['target'], 'ETH');
    expect(stop['contra'], 'USDC');
    expect(stop['qty'], '0.2');
    expect(stop['triggers'], [
      {'notionalPrice': '3000', 'triggerType': 'lower'},
    ]);
    expect(stop['funderAddress'], address);

    final limit = await TradeFlow.flashBody(
        {'kind': 'limit', 'sell': 'USDC', 'buy': 'ETH', 'amount': '100', 'usd': '1', 'price': '2800'},
        'limit', EvmChain.base, address);
    expect(limit['side'], 'buy');
    expect(limit['target'], 'ETH');
    expect(limit['qty'], '100');
    expect(limit['limitNotionalPrice'], '2800');

    final limitQty = await TradeFlow.flashBody(
        {'kind': 'limit', 'sell': 'USDC', 'buy': 'ETH', 'buyAmount': '0.1', 'price': '2800'},
        'limit', EvmChain.base, address);
    expect(limitQty['qty'], '280');

    final trail = await TradeFlow.flashBody(
        {'kind': 'trailing-stop', 'sell': 'ETH', 'buy': 'USDC', 'amount': '1', 'trail': '5'},
        'trailing-stop', EvmChain.base, address);
    expect(trail['trailingStop'], {'trailPercent': '0.05'});

    final twap = await TradeFlow.flashBody(
        {'kind': 'twap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '140', 'usd': '1', 'duration': '604800'},
        'twap', EvmChain.base, address);
    expect(twap['durationSeconds'], 604800);
    expect(twap['qty'], '140');

    final bracket = await TradeFlow.flashBody(
        {'kind': 'bracket', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.5', 'price': '4500', 'stopPrice': '3000'},
        'bracket', EvmChain.base, address);
    expect(bracket['orderType'], 'bracket');
    expect((bracket['triggers'] as List).length, 2);

    final bridge = await TradeFlow.flashBody(
        {'kind': 'bridge', 'sell': 'USDC', 'buy': 'USDC', 'amount': '50', 'chain': 'base', 'toChain': 'arbitrum'},
        'bridge', EvmChain.base, address);
    expect(bridge['orderType'], 'market');
    expect(bridge['targetChain'], 'arbitrum');
    expect(bridge['contraChain'], 'base');
    expect(bridge['recipientAddress'], address);
  });
}
