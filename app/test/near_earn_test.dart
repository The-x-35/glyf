import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/glyf_api.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_rpc.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/evm/trade_flow.dart';
import 'package:glyf/evm/trade_screen.dart';
import 'package:glyf/near/near_api.dart';
import 'package:glyf/near/near_earn.dart';
import 'package:glyf/near/near_flow.dart';
import 'package:glyf/near/near_pot.dart';
import 'package:glyf/near/near_views.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/flash_solana.dart';
import 'package:glyf/wallet/solana.dart';
import 'package:pinenacl/ed25519.dart' as ed;

// The person's wallets: the MetaMask address the live quotes below were
// asked for, and a Phantom one whose key the test holds (32 x 0x07).
const _evm = '0x2527D02599Ba641c19FEa793cD0F167589a0f10D';
const _sol = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _blockhash = '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd';
const _evmDeposit = '0x660Ec96a409AFd8243002689Ec5C4247738eAcB7';
const _solDeposit = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const _evmHash = '0xabababababababababababababababababababababababababababababababab';
const _gtUsdcp = '0x0bb69b79bc829e1cfcc34a740110886d98d2bd14';
const _kvMint = '5EBsGgVTubrd7ShJgE89k6nC2bnLzqGCjXb2ejrhtdBK';

const _gauntlet = {
  'id': 'gtusdcp',
  'name': 'Gauntlet USDC Prime',
  'protocol': 'Morpho',
  'chain': 'base',
  'chainName': 'Base',
  'receipt': 'gtUSDCp',
  'assetId': 'nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near',
  'underlying': 'USDC',
  'apy': 4.5,
  'apyBasis': 'net APY after the vault\'s fees',
  'apySource': 'Morpho',
  'default': true,
};

const _kamino = {
  'id': 'kamino-sol',
  'name': 'Kamino SOL Balanced',
  'protocol': 'Kamino',
  'chain': 'solana',
  'chainName': 'Solana',
  'receipt': 'kV-gtSOLb',
  'underlying': 'SOL',
  'apy': 4.24,
  'default': true,
};

/// POST /near/earn/quote {"coin":"USDC","amount":"50",refundTo,recipient},
/// as the live server answered it on 13 Nov 2026.
final _liveIn = jsonDecode(r'''
{"ok":true,"dry":false,"venue":"NEAR Intents","exact":"in",
 "sell":{"symbol":"USDC","chain":"base","decimals":6,"assetId":"nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near","address":"0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"},
 "buy":{"symbol":"gtUSDCp","chain":"base","decimals":18,"assetId":"nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near","address":"0x0bb69b79bc829e1cfcc34a740110886d98d2bd14"},
 "amountIn":"50","amountInBase":"50000000","amountInUsd":"49.98",
 "amountOut":"44505052.223666799396812103","amountOutBase":"44505052223666799396812103","amountOutUsd":"49.75",
 "minAmountOut":"44060001.701430131402843981","timeSeconds":52,
 "depositAddress":"0x660Ec96a409AFd8243002689Ec5C4247738eAcB7","depositMemo":null,"deadline":"2026-11-15T20:28:56.407Z",
 "deposit":{"kind":"erc20","chain":"base","chainId":8453,"to":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","value":"0","amountBase":"50000000",
   "token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","depositAddress":"0x660Ec96a409AFd8243002689Ec5C4247738eAcB7",
   "data":"0xa9059cbb000000000000000000000000660ec96a409afd8243002689ec5c4247738eacb70000000000000000000000000000000000000000000000000000000002faf080"},
 "explorer":"https://explorer.near-intents.org/transactions/0x660Ec96a409AFd8243002689Ec5C4247738eAcB7",
 "recipient":"0x2527D02599Ba641c19FEa793cD0F167589a0f10D","refundTo":"0x2527D02599Ba641c19FEa793cD0F167589a0f10D",
 "kind":"earn","direction":"in",
 "vault":{"id":"gtusdcp","name":"Gauntlet USDC Prime","protocol":"Morpho","chain":"base","chainName":"Base","receipt":"gtUSDCp",
   "assetId":"nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near","underlying":"USDC","apy":4.5,
   "apyBasis":"net APY after the vault's fees","apySource":"Morpho",
   "url":"https://app.morpho.org/base/vault/0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61/gauntlet-usdc-prime",
   "about":"Shares of Morpho's Gauntlet USDC Prime vault on Base","default":true},
 "words":"≈ $49.75 in Gauntlet USDC Prime at 4.5% APY"}
''') as Map<String, dynamic>;

/// POST /near/earn/quote {"coin":"USDC","amount":"20","direction":"out"}, live (dry).
final _liveOut = jsonDecode(r'''
{"ok":true,"dry":true,"venue":"NEAR Intents","exact":"out",
 "sell":{"symbol":"gtUSDCp","chain":"base","decimals":18,"assetId":"nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near","address":"0x0bb69b79bc829e1cfcc34a740110886d98d2bd14"},
 "buy":{"symbol":"USDC","chain":"base","decimals":6,"assetId":"nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near","address":"0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"},
 "amountIn":"18146730.018457475989616008","amountInBase":"18146730018457475989616008","amountInUsd":"20.29",
 "amountOut":"20","amountOutBase":"20000000","amountOutUsd":"19.99","minAmountOut":"20","timeSeconds":52,
 "depositAddress":null,"depositMemo":null,"deadline":null,"deposit":null,"explorer":null,"recipient":null,"refundTo":null,
 "kind":"earn","direction":"out",
 "vault":{"id":"gtusdcp","name":"Gauntlet USDC Prime","protocol":"Morpho","chain":"base","chainName":"Base","receipt":"gtUSDCp","apy":4.5},
 "words":"20 USDC back on Base from Gauntlet USDC Prime"}
''') as Map<String, dynamic>;

/// The live withdrawal made live: a deposit address, and the shares' own
/// ERC-20 transfer to it.
Map<String, dynamic> _outLive({String? amountInBase, String? amountOut, String exact = 'out', String? words}) {
  final base = amountInBase ?? _liveOut['amountInBase'] as String;
  return {
    ..._liveOut,
    'dry': false,
    'exact': exact,
    'amountInBase': base,
    'amountOut': ?amountOut,
    'words': ?words,
    'depositAddress': _evmDeposit,
    'deposit': {
      'kind': 'erc20',
      'chain': 'base',
      'chainId': 8453,
      'to': _gtUsdcp,
      'value': '0',
      'amountBase': base,
      'token': _gtUsdcp,
      'depositAddress': _evmDeposit,
    },
    'explorer': 'https://explorer.near-intents.org/transactions/$_evmDeposit',
  };
}

/// SOL into Kamino, live.
Map<String, dynamic> _solIn() => {
      'ok': true,
      'dry': false,
      'exact': 'in',
      'sell': {'symbol': 'SOL', 'chain': 'solana', 'decimals': 9, 'address': null},
      'buy': {'symbol': 'kV-gtSOLb', 'chain': 'solana', 'decimals': 9, 'address': _kvMint},
      'amountIn': '0.5',
      'amountInBase': '500000000',
      'amountInUsd': '40.79',
      'amountOut': '0.468478579',
      'amountOutUsd': '40.39',
      'timeSeconds': 32,
      'depositAddress': _solDeposit,
      'deposit': {'kind': 'sol', 'chain': 'solana', 'to': _solDeposit, 'lamports': '500000000'},
      'explorer': 'https://explorer.near-intents.org/transactions/$_solDeposit',
      'kind': 'earn',
      'direction': 'in',
      'vault': _kamino,
      'words': '≈ \$40.39 in Kamino SOL Balanced at 4.24% APY',
    };

class _FakeApi extends NearApi {
  _FakeApi(this.answer, {this.delivered = '20'});

  final Map<String, dynamic> Function(Map<String, Object?> body) answer;
  final String delivered;
  final bodies = <Map<String, Object?>>[];
  final swaps = <Map<String, Object?>>[];
  final submitted = <String>[];
  var polls = 0;

  @override
  Future<NearQuote> earnQuote(Map<String, Object?> body) async {
    bodies.add(body);
    return NearQuote.fromJson(answer(body));
  }

  @override
  Future<NearQuote> quote(Map<String, Object?> body) async {
    swaps.add(body);
    throw StateError('Earn never asks /near/quote');
  }

  @override
  Future<void> submit({required String depositAddress, required String txHash, String? memo}) async =>
      submitted.add('$depositAddress $txHash');

  @override
  Future<NearStatus> status({required String depositAddress, String? memo}) async {
    final s = ++polls == 1 ? 'PROCESSING' : 'SUCCESS';
    return NearStatus.fromJson({
      'status': s,
      if (s == 'SUCCESS') 'amountOut': delivered,
      if (s == 'SUCCESS') 'destinationTx': {'hash': '0xdead', 'url': 'https://basescan.org/tx/0xdead'},
      'explorer': 'https://explorer.near-intents.org/transactions/$depositAddress',
    });
  }
}

class _FakeWallet extends NearWallet {
  _FakeWallet({this.evm = _evm, this.sol = _sol, this.held});

  final String? evm;
  final String? sol;

  /// The shares the wallet holds, or null to fail the read.
  final BigInt? held;
  final sharesAsked = <String>[];
  final evmSteps = <SignStep>[];
  final solanaAsked = <Uint8List>[];
  final key = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 7)));

  @override
  Future<String?> evmAddress() async => evm;
  @override
  Future<String?> solanaAddress() async => sol;
  @override
  String get solanaName => 'Phantom';

  @override
  Future<BigInt> shares(EarnVault vault, String owner) async {
    sharesAsked.add('${vault.id} $owner');
    if (held == null) throw EvmRpcException('timeout');
    return held!;
  }

  @override
  Stream<SignEvent> signEvm(String title, List<SignStep> steps) async* {
    evmSteps.addAll(steps);
    yield SignEvent.progress('${steps.single.label}: confirm in MetaMask', reopen: 'metamask://');
    yield const SignEvent.done([Signed(hash: _evmHash)]);
  }

  @override
  Future<String> solanaBlockhash() async => _blockhash;

  @override
  Future<Uint8List> signSolana(Uint8List tx) async {
    solanaAsked.add(tx);
    final parts = FlashSvm.split(tx)!;
    final sig = key.sign(parts.message).signature.asTypedList;
    return Uint8List.fromList([...tx.sublist(0, 1), ...sig, ...parts.message]);
  }

  @override
  Future<String> sendSolana(Uint8List signed) async => Base58.encode(signed.sublist(1, 65));

  @override
  Future<bool?> confirmSolana(String signature) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;

  setUp(() {
    shared = {};
    NearFlow.pollEvery = Duration.zero;
    NearFlow.giveUpAfter = const Duration(minutes: 10);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
        case 'launchArgs':
          return <String>[];
      }
      return null;
    });
  });

  tearDown(() {
    NearFlow.api = const NearApi();
    NearFlow.wallet = const NearWallet();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  group('the earn quote’s answer', () {
    test('the live deposit quote reads its vault, APY and line', () {
      final q = NearQuote.fromJson(_liveIn);
      expect(q.isEarn, isTrue);
      expect(q.kind, 'earn');
      expect(q.direction, 'in');
      expect(q.exact, 'in');
      expect(q.words, '≈ \$49.75 in Gauntlet USDC Prime at 4.5% APY');
      final v = q.vault!;
      expect([v.id, v.name, v.protocol, v.chain, v.chainName, v.receipt],
          ['gtusdcp', 'Gauntlet USDC Prime', 'Morpho', 'base', 'Base', 'gtUSDCp']);
      expect(v.apy, 4.5);
      expect(v.apyText, '4.5% APY');
      // Still every field of a swap's quote: it deposits unchanged.
      expect(q.depositAddress, _evmDeposit);
      expect(q.deposit!.kind, 'erc20');
      expect(q.amountInBase, '50000000');
    });

    test('the live withdrawal and a vault with no APY', () {
      final q = NearQuote.fromJson(_liveOut);
      expect(q.direction, 'out');
      expect(q.exact, 'out');
      expect(q.words, '20 USDC back on Base from Gauntlet USDC Prime');
      expect(q.dry, isTrue);

      final taler = NearQuote.fromJson({
        ..._liveIn,
        'vault': {'id': 'taler-usdc', 'name': 'Taler USDC', 'protocol': 'Taler', 'chain': 'ethereum',
          'chainName': 'Ethereum', 'receipt': 'TLO', 'apy': null},
      });
      expect(taler.vault!.apy, isNull);
      expect(taler.vault!.apyText, 'APY n/a');
      expect(NearVault.fromJson(_kamino)!.apyText, '4.24% APY');
      expect(NearVault.fromJson({..._kamino, 'apy': 5})!.apyText, '5% APY');
    });

    test('a swap’s quote isn’t an Earn quote', () {
      final q = NearQuote.fromJson({..._liveIn}..remove('kind')..remove('vault')..remove('words'));
      expect(q.isEarn, isFalse);
      expect(q.vault, isNull);
    });
  });

  group('the pure parts', () {
    test('which vault: named, else the coin’s own', () {
      expect(NearEarn.vaultFor(coin: 'USDC'), NearEarn.gtusdcp);
      expect(NearEarn.vaultFor(coin: 'usdc'), NearEarn.gtusdcp);
      expect(NearEarn.vaultFor(coin: '\$'), isNull);
      expect(NearEarn.vaultFor(coin: 'SOL'), NearEarn.kaminoSol);
      expect(NearEarn.vaultFor(coin: 'USDC', vault: 'taler-usdc'), NearEarn.talerUsdc);
      expect(NearEarn.vaultFor(coin: 'USDC', vault: 'gtUSDCp'), NearEarn.gtusdcp);
      expect(NearEarn.vaultFor(coin: 'USDC', vault: 'steakusdc'), isNull);
      expect(NearEarn.vaultFor(coin: 'DOGE'), isNull);
      expect(NearEarn.gtusdcp.chain, 'base');
      expect(NearEarn.kaminoSol.chain, 'solana');
      expect(NearEarn.talerUsdc.chain, 'ethereum');
      expect(NearEarn.talerUsdc.decimals, 8);
    });

    test('in: shares land on the vault’s chain, a refund where the coins were; out: the other way', () {
      String? own(String c) => switch (c) { 'base' || 'ethereum' => _evm, 'solana' => _sol, _ => null };
      final usdcFromSolana = NearEarn.addresses(out: false, vaultChain: 'base', chain: 'solana', own: own);
      expect(usdcFromSolana.recipient, _evm);
      expect(usdcFromSolana.refundTo, _sol);
      final usdcToSolana = NearEarn.addresses(out: true, vaultChain: 'base', chain: 'solana', own: own);
      expect(usdcToSolana.refundTo, _evm);
      expect(usdcToSolana.recipient, _sol);
      final sol = NearEarn.addresses(out: false, vaultChain: 'solana', chain: 'solana', own: own);
      expect([sol.refundTo, sol.recipient], [_sol, _sol]);
      final toNear = NearEarn.addresses(out: true, vaultChain: 'base', chain: 'near', own: own);
      expect(toNear.refundTo, _evm);
      expect(toNear.recipient, isNull);
    });

    test('balanceOf: the calldata, and the node’s answer read', () {
      expect(NearEarn.balanceOfData(_evm),
          '0x70a08231' '0000000000000000000000002527d02599ba641c19fea793cd0f167589a0f10d');
      expect(() => NearEarn.balanceOfData('alice.near'), throwsArgumentError);
      expect(NearEarn.uint256('0x'), BigInt.zero);
      expect(NearEarn.uint256('0x0000000000000000000000000000000000000000000000000000000000000000'), BigInt.zero);
      // One whole gtUSDCp share (18 decimals).
      expect(NearEarn.uint256('0x0000000000000000000000000000000000000000000000000de0b6b3a7640000'),
          BigInt.parse('1000000000000000000'));
      expect(NearEarn.uint256(null), isNull);
      expect(NearEarn.uint256('nope'), isNull);
      expect(NearEarn.uint256('0xzz'), isNull);
    });

    test('the share balance is one eth_call through the app’s EVM RPC', () async {
      final asked = <Map<String, Object?>>[];
      final was = EvmRpc.post;
      addTearDown(() => EvmRpc.post = was);
      EvmRpc.post = (path, body) async {
        asked.add({'path': path, ...body});
        return {'result': '0x${BigInt.parse('17800000000000000000000000').toRadixString(16).padLeft(64, '0')}'};
      };
      final held = await NearEarn.erc20Balance(EvmChain.base, _gtUsdcp, _evm);
      expect(held, BigInt.parse('17800000000000000000000000'));
      expect(asked.single['path'], '/evm/rpc');
      expect(asked.single['chain'], 'base');
      expect(asked.single['method'], 'eth_call');
      expect(asked.single['params'], [
        {'to': _gtUsdcp, 'data': NearEarn.balanceOfData(_evm)},
        'latest',
      ]);

      EvmRpc.post = (path, body) async => {'error': {'message': 'execution reverted'}};
      await expectLater(NearEarn.erc20Balance(EvmChain.base, _gtUsdcp, _evm), throwsA(isA<EvmRpcException>()));
      EvmRpc.post = (path, body) async => {'result': null};
      await expectLater(NearEarn.erc20Balance(EvmChain.base, _gtUsdcp, _evm), throwsA(isA<EvmRpcException>()));
    });

    test('the words the keyboard hears', () {
      expect(NearEarn.done(out: false, amount: '50', coin: 'USDC', protocol: 'Morpho', chainName: 'Base'),
          ('Earning on 50 USDC', 'Morpho'));
      expect(NearEarn.done(out: false, amount: '0.5', coin: 'SOL', protocol: 'Kamino', chainName: 'Solana'),
          ('Earning on 0.5 SOL', 'Kamino'));
      expect(NearEarn.done(out: true, amount: '20', coin: 'USDC', protocol: 'Morpho', chainName: 'Base'),
          ('20 USDC back on Base', null));
      expect(NearEarn.done(out: true, amount: '20.012345', coin: 'USDC', protocol: 'Morpho', chainName: 'Base'),
          ('20.01 USDC back on Base', null));
      expect(NearEarn.done(out: true, amount: '0.46847857', coin: 'SOL', protocol: 'Kamino', chainName: 'Solana'),
          ('0.4685 SOL back on Solana', null));
      expect(NearEarn.coins('20.10', 'USDC'), '20.1');
      expect(NearEarn.coins('not a number', 'USDC'), 'not a number');
    });
  });

  group('NearFlow, kind=earn', () {
    Future<List<TradeOutcome>> run(Map<String, String> q) => NearFlow.run(q).toList();

    test('put 50 USDC to work: the live quote, MetaMask pays USDC, Earning on 50 USDC · Morpho', () async {
      final wallet = NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _liveIn);
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '50', 'title': 'Put 50 USDC to work'}).toList();

      expect(api.bodies.single, {
        'coin': 'USDC',
        'chain': 'base',
        'direction': 'in',
        'vault': 'gtusdcp',
        'amount': '50',
        'refundTo': _evm,
        'recipient': _evm,
        'slippage': 1.0,
      });
      expect(api.swaps, isEmpty);
      final step = wallet.evmSteps.single as TxStep;
      expect(step.call.to.toLowerCase(), '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913');
      expect(step.call.data, TradeFlow.erc20Transfer(_evmDeposit, BigInt.from(50000000)));
      expect(step.label, 'Send 50 USDC to NEAR Intents');
      expect(api.submitted, ['$_evmDeposit $_evmHash']);
      expect(wallet.sharesAsked, isEmpty);

      expect(out.map((o) => o.title), [
        'Asking NEAR Intents…',
        'Send 50 USDC to NEAR Intents: confirm in MetaMask',
        'Deposit sent',
        'Putting it into Gauntlet USDC Prime',
        'Earning on 50 USDC',
      ]);
      expect(out[3].detail, 'Deposit seen · ≈ \$49.75 in Gauntlet USDC Prime at 4.5% APY · about 52 s');
      final done = out.last as NearOutcome;
      expect(done.state, TradeState.done);
      expect(done.detail, 'Morpho');
      expect(done.quote!.isEarn, isTrue);
      // What the keyboard says back in the chat: "Earning on 50 USDC · Morpho".
      final told = jsonDecode(shared['walletOutcome'] as String) as Map;
      expect('${told['title']} · ${told['detail']}', 'Earning on 50 USDC · Morpho');
      // No raw share count anywhere a person reads.
      for (final o in out) {
        expect('${o.title} ${o.detail}', isNot(contains('44505052')));
      }
    });

    test('take 20 USDC out: exactly 20 back, the shares’ ERC-20 paid in MetaMask', () async {
      final wallet = NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _outLive(), delivered: '20');
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'amount': '20'}).toList();

      final body = api.bodies.single;
      expect(body['direction'], 'out');
      expect(body['amount'], '20');
      expect(body.containsKey('shares'), isFalse);
      expect(body['refundTo'], _evm, reason: 'the shares come back to the vault’s chain on a refund');
      expect(body['recipient'], _evm);
      final step = wallet.evmSteps.single as TxStep;
      expect(step.call.to, _gtUsdcp);
      expect(step.call.data, TradeFlow.erc20Transfer(_evmDeposit, BigInt.parse('18146730018457475989616008')));
      expect(step.label, 'Send \$20.29 of gtUSDCp to NEAR Intents');
      expect(out.map((o) => o.title), contains('Taking it out of Gauntlet USDC Prime'));
      expect(out.last.state, TradeState.done);
      expect(out.last.title, '20 USDC back on Base');
      expect(out.last.detail, isNull);
      expect(jsonDecode(shared['walletOutcome'] as String)['title'], '20 USDC back on Base');
      expect(jsonDecode(shared['walletOutcome'] as String).containsKey('detail'), isFalse);
    });

    test('take my USDC out of Earn: the share balance read first and sent as shares', () async {
      const held = '17800000000000000000000000';
      final wallet = NearFlow.wallet = _FakeWallet(held: BigInt.parse(held));
      final api = NearFlow.api = _FakeApi(
          (_) => _outLive(amountInBase: held, amountOut: '20.0123', exact: 'in',
              words: '20.0123 USDC back on Base from Gauntlet USDC Prime'),
          delivered: '20.012345');
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'all': '1'}).toList();

      expect(wallet.sharesAsked, ['gtusdcp $_evm']);
      final body = api.bodies.single;
      expect(body['shares'], held);
      expect(body.containsKey('amount'), isFalse);
      expect(out.first.title, 'Reading what’s in Earn…');
      expect((wallet.evmSteps.single as TxStep).call.data, TradeFlow.erc20Transfer(_evmDeposit, BigInt.parse(held)));
      expect(out.last.title, '20.01 USDC back on Base');
      expect(jsonDecode(shared['walletOutcome'] as String)['title'], '20.01 USDC back on Base');
    });

    test('everything out with no shares stops before any quote: Nothing in Earn yet', () async {
      final wallet = NearFlow.wallet = _FakeWallet(held: BigInt.zero);
      final api = NearFlow.api = _FakeApi((_) => _outLive());
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'all': '1'}).toList();
      expect(out.last.state, TradeState.failed);
      expect(out.last.title, 'Nothing in Earn yet');
      expect(api.bodies, isEmpty);
      expect(wallet.evmSteps, isEmpty);
      expect(jsonDecode(shared['walletOutcome'] as String)['title'], 'Nothing in Earn yet');
    });

    test('a share balance that can’t be read is said, and nothing is asked', () async {
      NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _outLive());
      final out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'all': '1'});
      expect(out.last.title, 'Couldn’t read what’s in Earn');
      expect(api.bodies, isEmpty);
    });

    test('a quote for other than every share is refused before MetaMask', () async {
      final wallet = NearFlow.wallet = _FakeWallet(held: BigInt.parse('17800000000000000000000000'));
      NearFlow.api = _FakeApi((_) => _outLive(amountInBase: '1000', exact: 'in'));
      final out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'all': '1'});
      expect(out.last.title, 'That quote isn’t for everything in Earn');
      expect(wallet.evmSteps, isEmpty);
    });

    test('a quote for another vault or coin is refused', () async {
      final wallet = NearFlow.wallet = _FakeWallet();
      final q = {'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '50'};
      NearFlow.api = _FakeApi((_) => {..._liveIn, 'vault': _kamino});
      expect((await run(q)).last.title, 'That quote isn’t for this trade');
      NearFlow.api = _FakeApi((_) => {..._liveIn}..remove('kind'));
      expect((await run(q)).last.title, 'That quote isn’t for this trade');
      NearFlow.api = _FakeApi((_) => {..._liveIn, 'amountInBase': '5000000'});
      expect((await run(q)).last.title, 'That quote isn’t for 50 USDC');
      expect(wallet.evmSteps, isEmpty);
    });

    test('put 0.5 SOL to work: Phantom pays SOL, the shares land in Phantom, Earning on 0.5 SOL · Kamino', () async {
      final wallet = NearFlow.wallet = _FakeWallet(evm: null);
      final api = NearFlow.api = _FakeApi((_) => _solIn(), delivered: '0.468478579');
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'SOL', 'amount': '0.5'}).toList();
      final body = api.bodies.single;
      expect(body['vault'], 'kamino-sol');
      expect(body['chain'], 'solana');
      expect(body['refundTo'], _sol);
      expect(body['recipient'], _sol);
      final asked = Sol.decodeLegacy(wallet.solanaAsked.single)!;
      expect(asked.feePayer, _sol);
      expect(asked.instructions.single.accounts[1].address, _solDeposit);
      expect(out.map((o) => o.title), contains('Send 0.5 SOL to NEAR Intents: approve in Phantom'));
      expect(out.last.title, 'Earning on 0.5 SOL');
      expect(out.last.detail, 'Kamino');
      final told = jsonDecode(shared['walletOutcome'] as String) as Map;
      expect('${told['title']} · ${told['detail']}', 'Earning on 0.5 SOL · Kamino');
    });

    test('take my SOL out of Earn reads the kV-gtSOLb balance of the Phantom address', () async {
      final wallet = NearFlow.wallet = _FakeWallet(evm: null, held: BigInt.from(468478579));
      final api = NearFlow.api = _FakeApi((_) => {
            ..._solIn(),
            'direction': 'out',
            'sell': {'symbol': 'kV-gtSOLb', 'chain': 'solana', 'decimals': 9, 'address': _kvMint},
            'buy': {'symbol': 'SOL', 'chain': 'solana', 'decimals': 9, 'address': null},
            'amountIn': '0.468478579',
            'amountInBase': '468478579',
            'amountOut': '0.4991',
            'deposit': {'kind': 'spl', 'chain': 'solana', 'to': _solDeposit, 'mint': _kvMint, 'amountBase': '468478579', 'decimals': 9},
          }, delivered: '0.49912');
      final out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'SOL', 'all': '1'});
      expect(wallet.sharesAsked, ['kamino-sol $_sol']);
      expect(api.bodies.single['shares'], '468478579');
      final tx = Sol.decodeLegacy(wallet.solanaAsked.single)!;
      expect(tx.instructions.last.program, Sol.tokenProgram);
      expect(tx.instructions.last.accounts[1].address, _kvMint);
      expect(out.last.title, '0.4991 SOL back on Solana');
    });

    test('USDC on Solana into the Base vault: Phantom refunds, the shares land in MetaMask', () async {
      NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _liveIn);
      await run({'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '50', 'chain': 'solana'});
      expect(api.bodies.single['chain'], 'solana');
      expect(api.bodies.single['refundTo'], _sol);
      expect(api.bodies.single['recipient'], _evm);
    });

    test('20 USDC out to Solana: the shares refund to MetaMask, the USDC lands in Phantom', () async {
      NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _outLive());
      await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'amount': '20', 'chain': 'solana'});
      expect(api.bodies.single['refundTo'], _evm);
      expect(api.bodies.single['recipient'], _sol);
    });

    test('a missing wallet is said as the swap says it, and nothing is asked', () async {
      final api = NearFlow.api = _FakeApi((_) => _liveIn);
      NearFlow.wallet = _FakeWallet(evm: null);
      var out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '50'});
      expect(out.single.title, 'MetaMask isn’t connected');
      expect(out.single.detail, EvmSigner.missing);
      out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC', 'all': '1'});
      expect(out.single.title, 'MetaMask isn’t connected');

      NearFlow.wallet = _FakeWallet(sol: null);
      out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'SOL', 'amount': '0.5'});
      expect(out.single.title, 'Phantom isn’t connected');
      expect(out.single.detail, 'Connect Phantom in Profile › Wallet');
      // The coins are in Phantom though the vault is on Base.
      out = await run({'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '50', 'chain': 'solana'});
      expect(out.single.title, 'Phantom isn’t connected');
      expect(api.bodies, isEmpty);
    });

    test('no amount, or a coin with no vault', () async {
      NearFlow.wallet = _FakeWallet();
      final api = NearFlow.api = _FakeApi((_) => _liveIn);
      expect((await run({'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC'})).single.title, 'How much?');
      expect((await run({'venue': 'near', 'kind': 'earn', 'direction': 'out', 'coin': 'USDC'})).single.detail,
          'Say an amount, like “take 20 usdc out of earn”');
      expect((await run({'venue': 'near', 'kind': 'earn', 'coin': 'DOGE', 'amount': '5'})).single.title,
          'Earn takes USDC or SOL');
      expect((await run({'venue': 'near', 'kind': 'earn', 'coin': 'USDC', 'amount': '5', 'vault': 'steakusdc'})).single.title,
          'Glyf doesn’t know that vault');
      expect(api.bodies, isEmpty);
    });

    test('the server’s refusal is said in its own words', () async {
      NearFlow.wallet = _FakeWallet();
      NearFlow.api = _RefusingApi();
      final out = await TradeFlow.run(
          {'venue': 'near', 'kind': 'earn', 'direction': 'in', 'coin': 'USDC', 'amount': '0.1'}).toList();
      expect(out.last.title, 'That didn’t go through');
      expect(out.last.detail, 'Too small for NEAR Intents: at least \$1');
    });
  });

  group('the trade screen on an Earn quote', () {
    Future<StreamController<TradeOutcome>> open(WidgetTester tester) async {
      final steps = StreamController<TradeOutcome>();
      await tester.pumpWidget(MaterialApp(
        home: TradeScreen(query: const {'kind': 'earn', 'venue': 'near'}, run: (_) => steps.stream),
      ));
      return steps;
    }

    testWidgets('in: the line, the vault and its APY, You pay, the risk line; never the share count', (tester) async {
      final steps = await open(tester);
      steps.add(NearOutcome(TradeState.working, 'Send 50 USDC to NEAR Intents: confirm in MetaMask',
          quote: NearQuote.fromJson(_liveIn), recipient: 'your wallet', reopen: 'metamask://'));
      await tester.pump();
      expect(find.text('≈ \$49.75 in Gauntlet USDC Prime at 4.5% APY'), findsOneWidget);
      expect(find.text('Gauntlet USDC Prime · Morpho'), findsOneWidget);
      expect(find.text('4.5% APY'), findsOneWidget);
      expect(find.text('You pay'), findsOneWidget);
      expect(find.text('50 USDC'), findsOneWidget);
      expect(find.text('You get'), findsNothing);
      expect(find.text('~52 s · via NEAR Intents'), findsOneWidget);
      expect(find.text(NearQuoteCard.earnRisk), findsOneWidget);
      expect(NearQuoteCard.earnRisk, 'Yield isn’t guaranteed; NEAR Intents doesn’t run the vault');
      expect(find.textContaining('44505052'), findsNothing);
      expect(find.textContaining('gtUSDCp'), findsNothing);
      unawaited(steps.close());
    });

    testWidgets('out: the line and You get exactly; a vault with no APY says APY n/a', (tester) async {
      final steps = await open(tester);
      steps.add(NearOutcome(TradeState.done, '20 USDC back on Base',
          quote: NearQuote.fromJson({..._outLive(), 'vault': {..._gauntlet, 'apy': null}}), recipient: 'your wallet'));
      await tester.pump();
      expect(find.text('20 USDC back on Base from Gauntlet USDC Prime'), findsOneWidget);
      expect(find.text('APY n/a'), findsOneWidget);
      expect(find.text('You get'), findsOneWidget);
      expect(find.text('20 USDC'), findsOneWidget, reason: 'exact out: no ≈');
      expect(find.text('to your wallet'), findsOneWidget);
      expect(find.text('You pay'), findsNothing);
      expect(find.textContaining('18146730'), findsNothing);
      unawaited(steps.close());
    });
  });

  group('the group pot setting', () {
    test('a Sputnik DAO, lowercase; a bare name made whole; anything else refused', () {
      expect(NearPot.key, 'nearPot');
      expect(NearPot.normalize('trip.sputnik-dao.near'), 'trip.sputnik-dao.near');
      expect(NearPot.normalize('  Trip.Sputnik-DAO.near '), 'trip.sputnik-dao.near');
      expect(NearPot.normalize('build'), 'build.sputnik-dao.near');
      expect(NearPot.normalize('lisbon-trip_2026'), 'lisbon-trip_2026.sputnik-dao.near');
      expect(NearPot.normalize(''), '');
      expect(NearPot.normalize('   '), '');
      expect(NearPot.normalize('alice.near'), isNull);
      expect(NearPot.normalize('trip.sputnik-dao.near.evil'), isNull);
      expect(NearPot.normalize('.sputnik-dao.near'), isNull);
      expect(NearPot.normalize('-trip.sputnik-dao.near'), isNull);
      expect(NearPot.normalize('a.b.sputnik-dao.near'), isNull);
      expect(NearPot.normalize('trip pot'), isNull);
      expect(NearPot.normalize('${'a' * 48}.sputnik-dao.near'), isNull, reason: 'over 64 characters');
    });
  });
}

class _RefusingApi extends NearApi {
  @override
  Future<NearQuote> earnQuote(Map<String, Object?> body) async =>
      throw GlyfApiException('Too small for NEAR Intents: at least \$1');
}
