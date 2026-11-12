import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/evm/trade_flow.dart';
import 'package:glyf/near/near_api.dart';
import 'package:glyf/near/near_flow.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/flash_solana.dart';
import 'package:glyf/wallet/solana.dart';
import 'package:pinenacl/ed25519.dart' as ed;

// The person's own wallets: a MetaMask address, and a Phantom one whose
// key the test holds (Keypair.fromSeed(32 x 0x07)) to sign as Phantom would.
const _evm = '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A';
const _sol = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _blockhash = '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd';
const _baseUsdc = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _evmDeposit = '0x78990000000000000000000000000000000000aa';
const _solDeposit = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const _evmHash = '0xabababababababababababababababababababababababababababababababab';

/// 1Click as Glyf's server answers for it (docs/NEAR-SPEC.md shapes).
class _FakeApi extends NearApi {
  _FakeApi(this.answer, {this.statuses = const ['PENDING_DEPOSIT', 'PROCESSING', 'SUCCESS'], this.delivered = '0.2438'});

  final Map<String, dynamic> Function(Map<String, Object?> body) answer;
  final List<String> statuses;

  /// What the status says arrived.
  final String delivered;
  final bodies = <Map<String, Object?>>[];
  final submitted = <String>[];
  var polls = 0;

  @override
  Future<NearQuote> quote(Map<String, Object?> body) async {
    bodies.add(body);
    return NearQuote.fromJson(answer(body));
  }

  @override
  Future<void> submit({required String depositAddress, required String txHash, String? memo}) async =>
      submitted.add('$depositAddress $txHash');

  @override
  Future<NearStatus> status({required String depositAddress, String? memo}) async {
    final s = statuses[polls < statuses.length ? polls : statuses.length - 1];
    polls++;
    return NearStatus.fromJson({
      'ok': true,
      'status': s,
      'done': s == 'SUCCESS' || s == 'REFUNDED' || s == 'FAILED',
      if (s == 'SUCCESS') 'amountOut': delivered,
      if (s == 'SUCCESS') 'destinationTx': {'hash': '5Sig', 'url': 'https://solscan.io/tx/5Sig'},
      'explorer': 'https://explorer.near-intents.org/transactions/$depositAddress',
    });
  }
}

/// MetaMask and Phantom, answering the way they do; nothing real is signed
/// but the Solana deposit, by the test's own key.
class _FakeWallet extends NearWallet {
  _FakeWallet({this.evm = _evm});

  final String? evm;
  final String sol = _sol;
  final evmSteps = <SignStep>[];
  final solanaAsked = <Uint8List>[];
  final solanaSent = <Uint8List>[];
  final key = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 7)));

  @override
  Future<String?> evmAddress() async => evm;
  @override
  Future<String?> solanaAddress() async => sol;
  @override
  String get solanaName => 'Phantom';

  @override
  Stream<SignEvent> signEvm(String title, List<SignStep> steps) async* {
    evmSteps.addAll(steps);
    yield SignEvent.progress('${steps.single.label}: confirm in MetaMask', reopen: 'metamask://');
    yield const SignEvent.progress('Waiting for Base…');
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
  Future<String> sendSolana(Uint8List signed) async {
    solanaSent.add(signed);
    return Base58.encode(signed.sublist(1, 65));
  }

  @override
  Future<bool?> confirmSolana(String signature) async => true;
}

Map<String, dynamic> _quote({
  String sell = 'USDC',
  String sellChain = 'base',
  int sellDecimals = 6,
  String? sellAddress = _baseUsdc,
  String buy = 'SOL',
  String buyChain = 'solana',
  String amountIn = '20',
  String amountInBase = '20000000',
  String amountOut = '0.2438',
  String depositAddress = _evmDeposit,
  String? memo,
  Map<String, dynamic>? deposit,
  Map<String, dynamic>? guard,
  bool dry = false,
}) =>
    {
      'ok': true,
      'dry': dry,
      'venue': 'NEAR Intents',
      'sell': {'symbol': sell, 'chain': sellChain, 'decimals': sellDecimals, 'address': sellAddress},
      'buy': {'symbol': buy, 'chain': buyChain, 'decimals': 9, 'address': null},
      'amountIn': amountIn,
      'amountInBase': amountInBase,
      'amountInUsd': '19.99',
      'amountOut': amountOut,
      'amountOutUsd': '19.88',
      'minAmountOut': '0.2413',
      'timeSeconds': 32,
      'depositAddress': depositAddress,
      'depositMemo': memo,
      'deadline': '2026-11-15T18:34:40Z',
      'deposit': deposit ??
          {
            'kind': 'erc20',
            'chain': 'base',
            'chainId': 8453,
            'to': _baseUsdc,
            'data': '0xa9059cbb',
            'value': '0',
            'amountBase': amountInBase,
            'token': _baseUsdc,
            'depositAddress': depositAddress,
          },
      'explorer': 'https://explorer.near-intents.org/transactions/$depositAddress',
      'guard': guard ?? {'level': 'ok', 'checks': []},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;
  late _FakeWallet wallet;

  setUp(() {
    shared = {};
    wallet = _FakeWallet();
    NearFlow.wallet = wallet;
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

  Future<List<TradeOutcome>> run(Map<String, String> q) => NearFlow.run(q).toList();

  test('Base USDC to SOL: quote, MetaMask deposit, submit, followed until it lands', () async {
    final api = NearFlow.api = _FakeApi((_) => _quote());
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'SOL', 'buyChain': 'solana', 'amount': '20'});

    // Refunds to the MetaMask address; the SOL lands in Phantom.
    final body = api.bodies.single;
    expect(body['refundTo'], _evm);
    expect(body['recipient'], _sol);
    expect(body['exact'], 'in');
    expect(body['sellChain'], 'base');
    expect(body['buyChain'], 'solana');
    expect(body['recent'], containsAll([_evm, _sol]));

    // The deposit is built here: USDC's transfer to the deposit address, exactly 20 USDC.
    final step = wallet.evmSteps.single as TxStep;
    expect(step.call.to, _baseUsdc);
    expect(step.call.data, TradeFlow.erc20Transfer(_evmDeposit, BigInt.from(20000000)));
    expect(step.chain.name, 'base');
    expect(api.submitted, ['$_evmDeposit $_evmHash']);

    expect(out.map((o) => o.title), [
      'Asking NEAR Intents…',
      'Send 20 USDC to NEAR Intents: confirm in MetaMask',
      'Waiting for Base…',
      'Deposit sent',
      'Swapping on NEAR Intents',
      'Swapped',
    ]);
    expect(out[1].reopen, 'metamask://');
    final done = out.last as NearOutcome;
    expect(done.state, TradeState.done);
    expect(done.detail, '20 USDC on Base → 0.2438 SOL on Solana');
    expect(done.txUrl, 'https://solscan.io/tx/5Sig');
    expect(done.explorer, 'https://explorer.near-intents.org/transactions/$_evmDeposit');
    expect(done.quote!.timeSeconds, 32);
    // Their own wallet isn't a new recipient to remember.
    expect(shared['nearRecent'], isNull);
  });

  test('SOL to Base USDC: Phantom signs the SOL transfer built here, checked before it is sent', () async {
    final api = NearFlow.api = _FakeApi((_) => _quote(
          sell: 'SOL',
          sellChain: 'solana',
          sellDecimals: 9,
          sellAddress: null,
          buy: 'USDC',
          buyChain: 'base',
          amountIn: '0.2',
          amountInBase: '200000000',
          amountOut: '19.8',
          depositAddress: _solDeposit,
          deposit: {'kind': 'sol', 'chain': 'solana', 'to': _solDeposit, 'lamports': '200000000'},
        ), delivered: '19.8');
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'SOL', 'chain': 'solana', 'buy': 'USDC', 'buyChain': 'base', 'amount': '0.2'});

    expect(api.bodies.single['refundTo'], _sol);
    expect(api.bodies.single['recipient'], _evm);
    final asked = Sol.decodeLegacy(wallet.solanaAsked.single)!;
    expect(asked.feePayer, _sol);
    expect(asked.instructions.single.program, Sol.systemProgram);
    expect(asked.instructions.single.accounts[1].address, _solDeposit);
    expect(wallet.solanaSent, hasLength(1));
    expect(api.submitted.single, startsWith('$_solDeposit '));
    expect(out.map((o) => o.title), contains('Send 0.2 SOL to NEAR Intents: approve in Phantom'));
    expect(out.last.state, TradeState.done);
    expect(out.last.detail, '0.2 SOL on Solana → 19.8 USDC on Base');
  });

  test('a Solana signature that isn’t the wallet’s stops it before anything is sent', () async {
    NearFlow.api = _FakeApi((_) => _quote(
        sell: 'SOL', sellChain: 'solana', sellDecimals: 9, sellAddress: null, buy: 'USDC', buyChain: 'base',
        amountIn: '0.2', amountInBase: '200000000', depositAddress: _solDeposit,
        deposit: {'kind': 'sol', 'chain': 'solana', 'to': _solDeposit, 'lamports': '200000000'}));
    NearFlow.wallet = _ForgingWallet();
    await expectLater(
        run({'kind': 'swap', 'venue': 'near', 'sell': 'SOL', 'chain': 'solana', 'buy': 'USDC', 'buyChain': 'base', 'amount': '0.2'}),
        throwsA(isA<SignFailed>()));
  });

  test('a refund is said in plain words, with where it went', () async {
    NearFlow.api = _FakeApi((_) => _quote(), statuses: ['PROCESSING', 'REFUNDED']);
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'SOL', 'buyChain': 'solana', 'amount': '20'});
    expect(out.last.state, TradeState.failed);
    expect(out.last.title, 'Refunded');
    expect(out.last.detail, 'NEAR Intents couldn’t fill it, so 20 USDC went back to 0x19E7…ff2A');
    expect(out.last.txUrl, contains('explorer.near-intents.org'));
  });

  test('Guard’s block stops it before MetaMask, until the person says send anyway', () async {
    final guard = {
      'level': 'block',
      'checks': [
        {'id': 'new-recipient', 'level': 'warn', 'text': 'You haven’t paid this address before'},
        {'id': 'lookalike', 'level': 'block', 'text': 'Looks like 0xAb12…9fE0 you paid before, but it isn’t'},
      ],
    };
    final q = {'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'ETH', 'buyChain': 'arbitrum',
      'amount': '20', 'to': '0xAb12000000000000000000000000000000009fE1'};
    NearFlow.api = _FakeApi((_) => _quote(buy: 'ETH', buyChain: 'arbitrum', guard: guard));
    final out = await run(q);
    final stop = out.last as NearOutcome;
    expect(stop.state, TradeState.failed);
    expect(stop.blocked, isTrue);
    expect(stop.title, 'Looks like 0xAb12…9fE0 you paid before, but it isn’t');
    expect(stop.detail, 'Nothing was sent');
    expect(stop.quote!.checks, hasLength(2));
    expect(wallet.evmSteps, isEmpty);

    final api = NearFlow.api = _FakeApi((_) => _quote(buy: 'ETH', buyChain: 'arbitrum', guard: guard));
    final anyway = await run({...q, 'anyway': '1'});
    expect(wallet.evmSteps, hasLength(1));
    expect(anyway.last.state, TradeState.done);
    expect(api.bodies.single['recipient'], '0xAb12000000000000000000000000000000009fE1');
    // Someone else paid: Guard knows them next time.
    expect(shared['nearRecent'], ['0xAb12000000000000000000000000000000009fE1']);
  });

  test('a .near name with no account is Guard’s block with nothing to send anyway', () async {
    // The server answers a recipient 1Click can't pay with a preview (no
    // deposit address) and Guard's block.
    final guard = {
      'level': 'block',
      'checks': [
        {'id': 'no-account', 'level': 'block', 'text': 'No NEAR account nobody-glyf-zz9.near'},
        {'id': 'new-recipient', 'level': 'warn', 'text': 'First time paying this address'},
      ],
    };
    final q = {'kind': 'send', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'USDC', 'buyChain': 'near',
      'amount': '5', 'exact': 'out', 'to': 'nobody-glyf-zz9.near'};
    for (final anyway in [false, true]) {
      NearFlow.api = _FakeApi((_) => _quote(buy: 'USDC', buyChain: 'near', dry: true, guard: guard));
      final stop = (await run({...q, if (anyway) 'anyway': '1'})).last as NearOutcome;
      expect(stop.state, TradeState.failed);
      expect(stop.title, 'No NEAR account nobody-glyf-zz9.near', reason: 'never “NEAR Intents gave no deposit address”');
      expect(stop.detail, 'Nothing was sent. Check the name');
      expect(stop.blocked, isFalse, reason: 'there is no deposit to send anyway');
      expect(wallet.evmSteps, isEmpty);
    }
  });

  test('from Bitcoin: the deposit address and amount to pay by hand, then followed', () async {
    const btcDeposit = 'bc1qdeposit0000000000000000000000000000000';
    final api = NearFlow.api = _FakeApi(
        (_) => _quote(
              sell: 'BTC',
              sellChain: 'bitcoin',
              sellDecimals: 8,
              sellAddress: null,
              buy: 'USDC',
              buyChain: 'base',
              amountIn: '0.01',
              amountInBase: '1000000',
              depositAddress: btcDeposit,
              deposit: {'kind': 'manual', 'chain': 'bitcoin', 'depositAddress': btcDeposit, 'amountBase': '1000000'},
            ),
        statuses: ['PENDING_DEPOSIT', 'PENDING_DEPOSIT', 'PROCESSING', 'SUCCESS']);
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'BTC', 'chain': 'bitcoin', 'buy': 'USDC', 'buyChain': 'base',
      'amount': '0.01', 'refundTo': 'bc1qmine'});
    expect(api.bodies.single['refundTo'], 'bc1qmine');
    expect(api.bodies.single['recipient'], _evm);
    final manual = out.whereType<NearOutcome>().firstWhere((o) => o.manual);
    expect(manual.title, 'Send from any wallet');
    expect(manual.detail, '0.01 BTC on Bitcoin to the address below');
    expect(manual.quote!.depositAddress, btcDeposit);
    expect(wallet.evmSteps, isEmpty);
    expect(api.submitted, isEmpty);
    expect(out.last.state, TradeState.done);
  });

  test('from Bitcoin with no refund address asks for one', () async {
    final api = NearFlow.api = _FakeApi((_) => _quote());
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'BTC', 'chain': 'bitcoin', 'buy': 'USDC', 'buyChain': 'base', 'amount': '0.01'});
    expect(out.single.title, 'Where should a refund go?');
    expect((out.single as NearOutcome).askRefund, 'Bitcoin', reason: 'the screen asks for it');
    expect(api.bodies, isEmpty);
  });

  test('to NEAR with no account asks for one; the saved nearAccount is used when there is one', () async {
    final api = NearFlow.api = _FakeApi((_) => _quote(buy: 'NEAR', buyChain: 'near'));
    final q = {'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'NEAR', 'buyChain': 'near', 'amount': '20'};
    final missing = await run(q);
    expect(missing.single.state, TradeState.failed);
    expect(missing.single.title, 'Who gets the NEAR?');
    expect(missing.single.detail, 'Add your NEAR account, like “to alice.near”');
    expect(api.bodies, isEmpty);

    shared['nearAccount'] = 'arpit.near';
    final out = await run(q);
    expect(api.bodies.single['recipient'], 'arpit.near');
    expect(out.last.state, TradeState.done);
  });

  test('a send pays the recipient exactly, from Base USDC, and remembers them', () async {
    shared['nearRecent'] = ['bob.near'];
    final api = NearFlow.api = _FakeApi((_) => _quote(buy: 'USDC', buyChain: 'near', amountIn: '5.03', amountInBase: '5030000', amountOut: '5'),
        delivered: '5');
    final out = await run({'kind': 'send', 'venue': 'near', 'exact': 'out', 'sell': 'USDC', 'chain': 'base', 'buy': 'USDC', 'buyChain': 'near',
      'amount': '5', 'to': 'alice.near'});
    final body = api.bodies.single;
    expect(body['exact'], 'out');
    expect(body['amount'], '5');
    expect(body['recipient'], 'alice.near');
    expect(body['recent'], containsAll(['bob.near', _evm]));
    // What it costs is the quote's: 5.03 USDC is what MetaMask sends.
    expect((wallet.evmSteps.single as TxStep).call.data, TradeFlow.erc20Transfer(_evmDeposit, BigInt.from(5030000)));
    expect(out.last.title, 'Sent');
    expect(out.last.detail, '5 USDC to alice.near on NEAR');
    expect(shared['nearRecent'], ['alice.near', 'bob.near']);
  });

  test('a quote that isn’t what was asked is refused before anything is signed', () async {
    final q = {'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'SOL', 'buyChain': 'solana', 'amount': '20'};
    NearFlow.api = _FakeApi((_) => _quote(amountInBase: '200000000'));
    expect((await run(q)).last.title, 'That quote isn’t for 20 USDC');
    NearFlow.api = _FakeApi((_) => _quote(buy: 'ETH'));
    expect((await run(q)).last.title, 'That quote isn’t for this trade');
    NearFlow.api = _FakeApi((_) => _quote(dry: true));
    expect((await run(q)).last.title, 'NEAR Intents gave no deposit address');
    // A deposit to another token than the one quoted.
    NearFlow.api = _FakeApi((_) => _quote(deposit: {
          'kind': 'erc20', 'chain': 'base', 'chainId': 8453, 'token': '0x0000000000000000000000000000000000000bad',
          'amountBase': '20000000', 'depositAddress': _evmDeposit,
        }));
    expect((await run(q)).last.title, 'That deposit doesn’t add up');
    expect(wallet.evmSteps, isEmpty);
  });

  test('a swap still going after the wait is said as sent, with its explorer', () async {
    NearFlow.giveUpAfter = Duration.zero;
    NearFlow.api = _FakeApi((_) => _quote(), statuses: ['PROCESSING']);
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'SOL', 'buyChain': 'solana', 'amount': '20'});
    expect(out.last.state, TradeState.submitted);
    expect(out.last.title, 'Still on its way');
    expect(out.last.txUrl, 'https://explorer.near-intents.org/transactions/$_evmDeposit');
  });

  test('MetaMask must be connected to pay from Base', () async {
    NearFlow.wallet = _FakeWallet(evm: null);
    NearFlow.api = _FakeApi((_) => _quote());
    final out = await run({'kind': 'swap', 'venue': 'near', 'sell': 'USDC', 'chain': 'base', 'buy': 'SOL', 'buyChain': 'solana', 'amount': '20'});
    expect(out.single.title, 'MetaMask isn’t connected');
  });

  test('the trade screen’s flow sends venue=near here, even a send from Solana', () async {
    NearFlow.api = _FakeApi((_) => _quote(
        sell: 'SOL', sellChain: 'solana', sellDecimals: 9, sellAddress: null, buy: 'USDC', buyChain: 'near',
        amountIn: '0.05', amountInBase: '50000000', depositAddress: _solDeposit,
        deposit: {'kind': 'sol', 'chain': 'solana', 'to': _solDeposit, 'lamports': '50000000'}));
    final out = await TradeFlow.run({'kind': 'send', 'venue': 'near', 'exact': 'out', 'sell': 'SOL', 'chain': 'solana',
      'buy': 'USDC', 'buyChain': 'near', 'amount': '10', 'to': 'bob.near'}).toList();
    expect(out.last.title, 'Sent');
    // The keyboard hears how it went.
    expect(jsonDecode(shared['walletOutcome'] as String)['title'], 'Sent');
  });

  test('the deposit for a chain’s own coin is a plain transfer of it', () {
    final quote = NearQuote.fromJson(_quote(
        sell: 'ETH', sellDecimals: 18, sellAddress: null, amountIn: '0.01', amountInBase: '10000000000000000',
        deposit: {'kind': 'native', 'chain': 'base', 'chainId': 8453, 'to': _evmDeposit, 'value': '10000000000000000', 'data': '0x'}));
    final call = NearFlow.depositCall(quote, EvmChain.base)!;
    expect(call.to, _evmDeposit);
    expect(call.value, BigInt.parse('10000000000000000'));
    expect(call.data, isNull);
  });

  test('a USDC deposit on Solana is TransferChecked to the deposit address’s token account', () {
    final quote = NearQuote.fromJson(_quote(
        sell: 'USDC', sellChain: 'solana', sellAddress: Sol.usdc, amountInBase: '20000000', depositAddress: _solDeposit,
        deposit: {'kind': 'spl', 'chain': 'solana', 'to': _solDeposit, 'mint': Sol.usdc, 'amountBase': '20000000', 'decimals': 6}));
    final tx = Sol.decodeLegacy(NearFlow.depositTransaction(quote, from: _sol, blockhash: _blockhash)!)!;
    expect(tx.instructions.last.program, Sol.tokenProgram);
    expect(tx.instructions.last.accounts[2].address, Sol.tokenAccount(_solDeposit, Sol.usdc));
  });
}

/// Phantom answering with a signature from some other key.
class _ForgingWallet extends _FakeWallet {
  @override
  Future<Uint8List> signSolana(Uint8List tx) async {
    final other = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 9)));
    final parts = FlashSvm.split(tx)!;
    return Uint8List.fromList([...tx.sublist(0, 1), ...other.sign(parts.message).signature.asTypedList, ...parts.message]);
  }
}
