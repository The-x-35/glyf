import 'dart:async';
import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/evm/metamask_link.dart';
import 'package:glyf/evm/trade_flow.dart';

/// Ethereum trades sign only in the person's own wallet (MetaMask, by its
/// deeplinks): Glyf holds no key, builds each request, and checks what
/// comes back. "MetaMask" here is the test, signing with a made-up key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;
  late List<String> opened;
  late List<String> calls;

  // Stands in for the key inside MetaMask; never one Glyf has.
  const walletKey = '0x1111111111111111111111111111111111111111111111111111111111111111';
  final wallet = EthSigUtil.recoverPersonalSignature(
      signature: EthSigUtil.signPersonalMessage(privateKey: walletKey, message: Uint8List.fromList([1])),
      message: Uint8List.fromList([1]));

  setUp(() {
    shared = {};
    opened = [];
    calls = [];
    MetaMaskLink.walletChain = null;
    EvmSigner.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call.method);
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
        case 'launchArgs':
          return <String>[];
        case 'openMetaMask':
          opened.add(args['url'] as String);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  /// The request MetaMask was opened on: its id, method and params.
  Map<String, dynamic> request(String url) {
    final message = Uri.parse(url).queryParameters['message']!;
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(base64.decode(base64.normalize(message)))) as Map);
  }

  /// MetaMask answering on glyf://mmsdk, the way it does.
  void answer(String id, Object? result) {
    final data = {'id': id, 'result': result, 'accounts': [wallet], 'chainId': '0x2105'};
    final message = base64.encode(utf8.encode(jsonEncode({'data': data})));
    expect(MetaMaskLink.handle(Uri.parse('glyf://mmsdk?message=${Uri.encodeComponent(message)}')), isTrue);
  }

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

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
    'message': {'qty': '50000000', 'owner': '0x1111111111111111111111111111111111111111'},
  };

  test('MetaMask is the only Ethereum signer; there is no Glyf wallet', () {
    expect(EvmSignerKind.values, [EvmSignerKind.metamask]);
    expect(EvmSigner.kindOf('glyf'), isNull);
    expect(EvmSigner.kindOf('metamask'), EvmSignerKind.metamask);
  });

  test('nothing signs before MetaMask is connected, and nothing opens', () async {
    // An older build's own wallet, still in shared settings: not a signer.
    shared = {'evmSigner': 'glyf', 'walletMode': 'internal', 'evmAddress': '0x2222222222222222222222222222222222222222'};
    await expectLater(
      EvmSigner.run('Sign', [TypedStep(EvmChain.base, 'Sign the order', typed)]).toList(),
      throwsA(isA<SignFailed>().having((e) => e.title, 'title', 'MetaMask isn’t connected')),
    );
    expect(opened, isEmpty);
  });

  test('an older build’s own-wallet settings are rewritten for MetaMask', () {
    expect(EvmSigner.needsRewrite({'evmSigner': 'glyf', 'evmAddress': '0x22'}, null), isTrue);
    expect(EvmSigner.needsRewrite({'evmSigner': 'metamask', 'walletMode': 'internal'}, null), isTrue);
    expect(EvmSigner.needsRewrite({'evmSigner': 'metamask', 'evmAddress': wallet}, wallet), isFalse);
    final s = EvmSigner.shared(
        {'evmSigner': 'glyf', 'walletMode': 'internal', 'evmAddress': '0x22', 'other': 1}, const {}, null);
    expect(s, {'evmSigner': 'metamask', 'evmWallets': <String, String>{}, 'other': 1});
    final connected = EvmSigner.shared({}, {EvmSignerKind.metamask: wallet}, wallet);
    expect(connected['evmAddress'], wallet);
    expect(connected['evmWallets'], {'metamask': wallet});
  });

  test('typed data goes to MetaMask, led by a chain switch, and its signature is checked', () async {
    shared = {'evmWallets': {'metamask': wallet}};
    final events = <SignEvent>[];
    final done = Completer<void>();
    EvmSigner.run('Stop-loss', [TypedStep(EvmChain.base, 'Sign the stop-loss', typed)]).listen(events.add,
        onError: done.completeError, onDone: done.complete);
    await until(() => opened.isNotEmpty);

    expect(opened.single, startsWith('metamask://mmsdk?'));
    final asked = request(opened.single);
    expect(asked['method'], 'metamask_batch');
    final batch = (asked['params'] as List).cast<Map>();
    expect(batch[0]['method'], 'wallet_switchEthereumChain');
    expect(batch[0]['params'], [
      {'chainId': '0x2105'},
    ]);
    expect(batch[1]['method'], 'eth_signTypedData_v4');
    expect(batch[1]['params'][0], wallet);

    final signature = EthSigUtil.signTypedData(privateKey: walletKey, jsonData: jsonEncode(typed), version: TypedDataVersion.V4);
    answer('${asked['id']}', [null, signature]);
    await done.future;
    expect(events.last.results!.single.signature, signature);
    expect(events.any((e) => e.reopen == MetaMaskLink.home), isTrue);
    // Glyf never asked the phone for a key.
    expect(calls.where((m) => m.startsWith('walletSecret')), isEmpty);
  });

  test('a signature from anyone but the connected wallet is refused', () async {
    shared = {'evmWallets': {'metamask': wallet}};
    MetaMaskLink.walletChain = '0x2105'; // already on Base: no switch
    final done = Completer<Object?>();
    EvmSigner.run('Cancel', [MessageStep(EvmChain.base, 'Cancel the order', 'Definitive Flash v1 — Cancel Order\nOrder: 1')])
        .listen((_) {}, onError: (Object e) => done.isCompleted ? null : done.complete(e),
            onDone: () => done.isCompleted ? null : done.complete(null));
    await until(() => opened.isNotEmpty);
    final asked = request(opened.single);
    expect(asked['method'], 'personal_sign');
    const otherKey = '0x2222222222222222222222222222222222222222222222222222222222222222';
    final forged = EthSigUtil.signPersonalMessage(
        privateKey: otherKey, message: Uint8List.fromList(utf8.encode('Definitive Flash v1 — Cancel Order\nOrder: 1')));
    answer('${asked['id']}', forged);
    final error = await done.future;
    expect(error, isA<SignFailed>().having((e) => e.title, 'title', startsWith('That signature isn’t from')));
  });

  test('a transaction MetaMask sent counts only when it is from the wallet, to the contract asked for', () {
    const router = '0x2626664c2603336E57B271c5C0b26F421741e481';
    expect(EvmSigner.receiptMatches({'from': wallet.toLowerCase(), 'to': router.toLowerCase()}, from: wallet, to: router),
        isTrue);
    expect(EvmSigner.receiptMatches({'from': '0x2222222222222222222222222222222222222222', 'to': router}, from: wallet, to: router),
        isFalse);
    expect(EvmSigner.receiptMatches({'from': wallet, 'to': '0x3333333333333333333333333333333333333333'}, from: wallet, to: router),
        isFalse);
  });

  test('a transaction step is eth_sendTransaction for MetaMask to send, never a raw one', () {
    final tx = EvmSigner.txJson(wallet, EvmCall(to: '0x2626664c2603336E57B271c5C0b26F421741e481', data: '0x1234', value: BigInt.from(16)));
    expect(tx, {'from': wallet, 'to': '0x2626664c2603336E57B271c5C0b26F421741e481', 'data': '0x1234', 'value': '0x10'});
    expect(() => EvmSigner.signRpc(wallet, TxStep(EvmChain.base, 'Swap', EvmCall(to: wallet))), throwsArgumentError);
  });

  test('addresses get their EIP-55 checksum', () {
    // EIP-55's own examples.
    expect(EvmSigner.checksum('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'), '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
    expect(EvmSigner.checksum('0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359'), '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359');
    expect(EvmSigner.checksum('not an address'), 'not an address');
  });

  test('a pay request is not a trade: refused before any wallet is asked', () async {
    final out = await TradeFlow.run({'kind': 'request', 'sell': 'USDT', 'amount': '5'}).toList();
    expect(out.single.state, TradeState.failed);
    expect(opened, isEmpty);
    expect(calls.where((m) => m.startsWith('walletSecret')), isEmpty);
  });

  test('a send to a name needs MetaMask connected, and a Solana send is Phantom’s', () async {
    final eth = await TradeFlow.run({'kind': 'send', 'sell': 'USDC', 'amount': '5', 'to': 'vitalik.eth', 'chain': 'base'}).toList();
    expect(eth.single.title, 'MetaMask isn’t connected');
    final sol = await TradeFlow.run({'kind': 'send', 'sell': 'SOL', 'amount': '1', 'to': 'arpit.sol', 'chain': 'solana'}).toList();
    expect(sol.single.state, TradeState.failed);
    expect(sol.single.title, 'Send it from Phantom');
    expect(opened, isEmpty);
  });

  test('a send’s name resolves to its own record on the chain, else its Ethereum one', () {
    const answer = {
      'addresses': {
        'ethereum': '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
        'base': '0x1111111111111111111111111111111111111111',
        'solana': '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU',
      }
    };
    expect(TradeFlow.recipientFrom(answer, EvmChain.base), '0x1111111111111111111111111111111111111111');
    expect(TradeFlow.recipientFrom(answer, EvmChain.unichain), '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045');
    expect(TradeFlow.recipientFrom(const {'addresses': {'solana': '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU'}}, EvmChain.base),
        isNull);
    expect(TradeFlow.recipientFrom(const {'addresses': {'base': '0x12'}}, EvmChain.base), isNull);
  });

  test('a send is a plain transfer of ETH, or the token’s ERC-20 transfer', () {
    const to = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
    final eth = TradeFlow.sendCall(chain: EvmChain.base, to: to, symbol: 'ETH', amount: '0.01', tokens: const [])!;
    expect(eth.to, to);
    expect(eth.value, BigInt.parse('10000000000000000'));
    expect(eth.data, isNull);
    const usdc = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
    final tokens = [
      {'symbol': 'ETH', 'address': '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 'decimals': 18, 'native': true},
      {'symbol': 'USDC', 'address': usdc, 'decimals': 6},
    ];
    final token = TradeFlow.sendCall(chain: EvmChain.base, to: to, symbol: 'usdc', amount: '20.5', tokens: tokens)!;
    expect(token.to, usdc);
    expect(token.value, BigInt.zero);
    expect(token.data,
        '0xa9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045'
        '000000000000000000000000000000000000000000000000000000000138ce20');
    expect(TradeFlow.sendCall(chain: EvmChain.base, to: to, symbol: 'PEPE', amount: '1', tokens: tokens), isNull);
    // A token picked by its address in the keyboard is that token, not a lookalike symbol.
    expect(TradeFlow.sendCall(chain: EvmChain.base, to: to, symbol: 'USDC', amount: '1', tokens: tokens, tokenAddress: usdc)?.to,
        usdc);
    expect(TradeFlow.sendCall(
            chain: EvmChain.base, to: to, symbol: 'USDC', amount: '1', tokens: tokens,
            tokenAddress: '0x2222222222222222222222222222222222222222'),
        isNull);
    expect(TradeFlow.units('1.2345678', 6), BigInt.from(1234567));
  });

  test('a name that points elsewhere than the keyboard showed stops the send before MetaMask', () async {
    shared = {'evmWallets': {'metamask': wallet}};
    final asked = <String>[];
    final real = TradeFlow.evmGet;
    addTearDown(() => TradeFlow.evmGet = real);
    TradeFlow.evmGet = (path) async {
      asked.add(path);
      return {
        'addresses': {'ethereum': '0x3333333333333333333333333333333333333333'}
      };
    };
    final out = await TradeFlow.run({
      'kind': 'send', 'sell': 'USDC', 'amount': '5', 'to': 'vitalik.eth', 'chain': 'base',
      'address': '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
    }).toList();
    expect(asked.single, '/names/resolve?name=vitalik.eth');
    expect(out.last.state, TradeState.failed);
    expect(out.last.title, 'vitalik.eth points somewhere else now');
    expect(opened, isEmpty);
  });

  test('an Ethereum trade without MetaMask says to connect it', () async {
    final out = await TradeFlow.run({'kind': 'swap', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.1', 'chain': 'base'}).toList();
    expect(out.single.state, TradeState.failed);
    expect(out.single.title, 'MetaMask isn’t connected');
    expect(out.single.detail, EvmSigner.missing);
    expect(opened, isEmpty);
  });

  const address = '0x1111111111111111111111111111111111111111';

  test('the keyboard’s words become Flash’s order body', () async {
    Future<Map<String, Object?>> body(Map<String, String> q, String kind) => TradeFlow.flashBodyOn(q, kind, 'base', address,
        toChain: EvmChain.named(q['toChain'])?.name, allOf: (_) async => '0', priceOf: (_) async => 3000);
    final stop = await body({'kind': 'stop-loss', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.2', 'price': '3000', 'chain': 'base'},
        'stop-loss');
    expect(stop['orderType'], 'stop-loss');
    expect(stop['side'], 'sell');
    expect(stop['target'], 'ETH');
    expect(stop['contra'], 'USDC');
    expect(stop['qty'], '0.2');
    expect(stop['triggers'], [
      {'notionalPrice': '3000', 'triggerType': 'lower'},
    ]);
    expect(stop['funderAddress'], address);

    final limit = await body({'kind': 'limit', 'sell': 'USDC', 'buy': 'ETH', 'amount': '100', 'usd': '1', 'price': '2800'}, 'limit');
    expect(limit['side'], 'buy');
    expect(limit['target'], 'ETH');
    expect(limit['qty'], '100');
    expect(limit['limitNotionalPrice'], '2800');

    final limitQty = await body({'kind': 'limit', 'sell': 'USDC', 'buy': 'ETH', 'buyAmount': '0.1', 'price': '2800'}, 'limit');
    expect(limitQty['qty'], '280');

    final trail = await body({'kind': 'trailing-stop', 'sell': 'ETH', 'buy': 'USDC', 'amount': '1', 'trail': '5'}, 'trailing-stop');
    expect(trail['trailingStop'], {'trailPercent': '0.05'});

    final twap = await body({'kind': 'twap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '140', 'usd': '1', 'duration': '604800'}, 'twap');
    expect(twap['durationSeconds'], 604800);
    expect(twap['qty'], '140');

    final bracket =
        await body({'kind': 'bracket', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.5', 'price': '4500', 'stopPrice': '3000'}, 'bracket');
    expect(bracket['orderType'], 'bracket');
    expect((bracket['triggers'] as List).length, 2);

    final move = await body(
        {'kind': 'bridge', 'sell': 'USDC', 'buy': 'USDC', 'amount': '50', 'chain': 'base', 'toChain': 'arbitrum'}, 'bridge');
    expect(move['orderType'], 'market');
    expect(move['targetChain'], 'arbitrum');
    expect(move['contraChain'], 'base');
    expect(move['recipientAddress'], address);
  });

  test('a Solana order is the same body on solana, its "all" and prices from Phantom’s side', () async {
    const funder = 'DYbqrJ7eRQNi4kb4suurTovK2wXxSq87ujuAeLDroQ69';
    final asked = <String>[];
    Future<String> allOf(String s) async => s == 'SOL' ? '1.25' : throw StateError(s);
    Future<double> priceOf(String s) async {
      asked.add(s);
      return 90;
    }

    final stop = await TradeFlow.flashBodyOn(
        {'kind': 'stop-loss', 'sell': 'SOL', 'buy': 'USDC', 'price': '100', 'chain': 'solana'}, 'stop-loss', 'solana', funder,
        allOf: allOf, priceOf: priceOf);
    expect(stop['targetChain'], 'solana');
    expect(stop['contraChain'], 'solana');
    expect(stop['target'], 'SOL');
    expect(stop['qty'], '1.25');
    expect(stop['funderAddress'], funder);

    // "buy 0.1 sol, tp 200, sl 100": a market buy at today's price, the
    // pair attached; 200 is the take-profit, not what the buy pays.
    final bracket = await TradeFlow.flashBodyOn(
        {'kind': 'bracket', 'sell': 'USDC', 'buy': 'SOL', 'buyAmount': '0.1', 'price': '200', 'stopPrice': '100'},
        'bracket', 'solana', funder,
        allOf: allOf, priceOf: priceOf);
    expect(bracket['orderType'], 'market');
    expect(bracket['side'], 'buy');
    expect(bracket['qty'], '9');
    expect(asked, ['SOL']);
    expect(bracket['attachedBracket'], {
      'takeProfit': {'notionalPrice': '200'},
      'stopLoss': {'notionalPrice': '100'},
    });
  });

  test('a token picked in the keyboard rides by its address in a Flash order', () async {
    const pepe = '0xB4fDe59a779991bfB6a52253B51947828b982be3';
    final body = await TradeFlow.flashBodyOn(
        {'kind': 'limit', 'sell': 'USDC', 'buy': 'PEPE', 'buyAddress': pepe, 'amount': '20', 'usd': '1', 'price': '0.00001'},
        'limit', 'base', address,
        allOf: (_) async => '0', priceOf: (_) async => 0.00001);
    expect(body['target'], pepe);
    expect(body['contra'], 'USDC');
    expect(body['side'], 'buy');
  });
}
