import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/near/hot_wallet.dart';
import 'package:glyf/wallet/base58.dart';

/// HOT's relay (h4n.app) and clock as a test: what was posted, how often
/// the answer was asked for, and the answers to give, in turn.
class _FakeRelay {
  _FakeRelay({this.answers = const []});

  /// GET /{id}/response bodies in turn (the last repeats); null = `{"data":null}`.
  final List<Object?> answers;
  final String ts = '1794511234494864516000';
  final posts = <(Uri, Map<String, dynamic>)>[];
  final gets = <Uri>[];

  Future<(int, String)> call(String method, Uri url, {String? body}) async {
    if (url.toString() == HotRelay.timeUrl) return (200, jsonEncode({'ts': ts}));
    if (method == 'POST') {
      posts.add((url, jsonDecode(body!) as Map<String, dynamic>));
      return (200, '{"ok":true}');
    }
    gets.add(url);
    final a = answers.isEmpty ? null : answers[gets.length - 1 < answers.length ? gets.length - 1 : answers.length - 1];
    if (a is Exception) throw a;
    return (200, jsonEncode({'data': a == null ? null : jsonEncode(a)}));
  }

  /// The request HOT would read from the last POST.
  Map<String, dynamic> get request {
    final query = posts.last.$2['data'] as String;
    return jsonDecode(utf8.decode(Base58.decode(query)!)) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;
  late List<String> opened;

  setUp(() {
    shared = {};
    opened = [];
    HotWallet.open = (url) async {
      opened.add(url);
      return true;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    HotWallet.relay = HotRelay();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  HotRelay relayOf(_FakeRelay fake, {Duration every = Duration.zero}) =>
      HotWallet.relay = HotRelay(http: fake.call, pollEvery: every);

  test('a request is near-connect’s: base58 of the JSON, its id the SHA-1 hex of that text, the hotcall link', () {
    final call = HotRelay.encode('near:signIn', <String, Object?>{},
        deadline: 1794511294494, uuid: '0b7c2d5e-1f3a-4b6c-8d9e-0f1a2b3c4d5e', origin: 'https://tryglyf.com');
    final json = utf8.decode(Base58.decode(call.query)!);
    // Key order as near-connect's spread makes it: {...request, deadline, id, $hot, origin}.
    expect(json,
        '{"method":"near:signIn","request":{},"deadline":1794511294494,"id":"0b7c2d5e-1f3a-4b6c-8d9e-0f1a2b3c4d5e","\$hot":true,"origin":"https://tryglyf.com"}');
    expect(call.id, sha1.convert(utf8.encode(call.query)).toString());
    expect(call.id, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(call.link, 'https://app.hot-labs.org/link?hotcall-${call.id}');
  });

  test('create POSTs {"data": query} to h4n.app/{id}/request, with HOT’s clock plus 60 s as the deadline', () async {
    final fake = _FakeRelay();
    final call = await relayOf(fake).create('near:signIn', <String, Object?>{});
    final (url, body) = fake.posts.single;
    expect(url.toString(), 'https://h4n.app/${call.id}/request');
    expect(body, {'data': call.query});
    final r = fake.request;
    expect(r['method'], 'near:signIn');
    expect(r['request'], <String, Object?>{});
    expect(r[r'$hot'], true);
    expect(r['origin'], 'https://tryglyf.com');
    expect(r['id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    // ts is in 10^-12 s: 1794511234 s, so the deadline is 1794511294000 ms
    // (HOT's second, plus the few ms the test took).
    expect(r['deadline'], inInclusiveRange(1794511294000, 1794511294000 + 2000));
  });

  test('wait polls GET /{id}/response until HOT answers, and gives its payload', () async {
    final fake = _FakeRelay(answers: [null, Exception('dropped'), null, {'success': true, 'payload': {'ok': 1}}]);
    final relay = relayOf(fake);
    final call = await relay.create('near:signMessage', {'message': 'hi'});
    expect(await relay.wait(call), {'ok': 1});
    expect(fake.gets, hasLength(4));
    expect(fake.gets.every((u) => u.toString() == 'https://h4n.app/${call.id}/response'), isTrue);
  });

  test('no answer in time is HOT Wallet didn’t answer; a refusal is HOT’s words, marked refused', () async {
    final relay = relayOf(_FakeRelay());
    final call = await relay.create('near:signIn', <String, Object?>{});
    await expectLater(relay.wait(call, timeout: Duration.zero),
        throwsA(isA<HotError>().having((e) => e.timedOut, 'timedOut', true).having((e) => e.message, 'message', 'HOT Wallet didn’t answer')));

    final no = relayOf(_FakeRelay(answers: [{'success': false, 'payload': 'Rejected by user'}]));
    final asked = await no.create('near:signIn', <String, Object?>{});
    await expectLater(no.wait(asked),
        throwsA(isA<HotError>().having((e) => e.refused, 'refused', true).having((e) => e.message, 'message', 'Rejected by user')));

    final bare = relayOf(_FakeRelay(answers: [{'success': false, 'payload': null}]));
    final c = await bare.create('near:signIn', <String, Object?>{});
    await expectLater(bare.wait(c), throwsA(isA<HotError>().having((e) => e.message, 'message', 'Cancelled in HOT Wallet')));
  });

  test('coming back to the app asks at once, not at the next tick; Stop ends the wait', () async {
    final fake = _FakeRelay(answers: [{'success': true, 'payload': 'yes'}]);
    final relay = relayOf(fake, every: const Duration(hours: 1));
    final call = await relay.create('near:signIn', <String, Object?>{});
    final answer = relay.wait(call);
    await Future<void>.delayed(Duration.zero);
    expect(fake.gets, isEmpty);
    HotRelay.wake();
    expect(await answer, 'yes');

    final stop = Completer<void>();
    final waiting = relayOf(_FakeRelay(), every: const Duration(hours: 1));
    final c = await waiting.create('near:signIn', <String, Object?>{});
    final w = waiting.wait(c, stop: stop.future);
    stop.complete();
    await expectLater(w, throwsA(isA<HotError>().having((e) => e.stopped, 'stopped', true)));
  });

  test('Connect: near:signIn opens HOT, keeps the account and key, and leaves MetaMask and Phantom alone', () async {
    shared = {'walletAddress': 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB', 'evmAddress': '0x19E7', 'evmSigner': 'metamask', 'haptics': false};
    final fake = _FakeRelay(answers: [null, {'success': true, 'payload': {'accountId': 'arpit.near', 'publicKey': 'ed25519:7xKX'}}]);
    relayOf(fake);
    final links = <String>[];
    final a = await HotWallet.connect(opened: links.add);
    expect(fake.request['method'], 'near:signIn');
    expect(opened.single, startsWith('https://app.hot-labs.org/link?hotcall-'));
    expect(links, opened);
    expect(a.accountId, 'arpit.near');
    expect(HotWallet.account.value?.accountId, 'arpit.near');
    expect(shared, {
      'walletAddress': 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB',
      'evmAddress': '0x19E7',
      'evmSigner': 'metamask',
      'haptics': false,
      'nearAccount': 'arpit.near',
      'nearPublicKey': 'ed25519:7xKX',
      'nearWallet': 'hot',
    });
    expect((await HotWallet.load())?.publicKey, 'ed25519:7xKX');

    await HotWallet.disconnect();
    expect(shared, {'walletAddress': 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB', 'evmAddress': '0x19E7', 'evmSigner': 'metamask', 'haptics': false});
    expect(HotWallet.account.value, isNull);
  });

  test('MetaMask connecting or leaving keeps the NEAR account HOT left', () {
    final s = {'nearAccount': 'arpit.near', 'nearPublicKey': 'ed25519:7xKX', 'nearWallet': 'hot', 'walletAddress': 'Gma'};
    final on = EvmSigner.shared(Map.of(s), {EvmSignerKind.metamask: '0x19E7'}, '0x19E7');
    expect(on, containsPair('nearAccount', 'arpit.near'));
    expect(on, containsPair('walletAddress', 'Gma'));
    final off = EvmSigner.shared(Map.of(s), const {}, null);
    expect(off, containsPair('nearAccount', 'arpit.near'));
    expect(off, containsPair('nearPublicKey', 'ed25519:7xKX'));
  });

  test('an answer that isn’t a NEAR account is refused and nothing is kept', () async {
    relayOf(_FakeRelay(answers: [{'success': true, 'payload': {'accountId': 'Not An Account'}}]));
    await expectLater(HotWallet.connect(), throwsA(isA<HotError>()));
    expect(shared.containsKey('nearAccount'), isFalse);
  });

  test('NEAR and NEP-141 transfers are near-connect’s JSON actions, amounts in yocto as text', () {
    expect(NearTransaction.nearTransfer('bob.near', BigInt.parse('2000000000000000000000000')).toJson(), {
      'receiverId': 'bob.near',
      'actions': [
        {'type': 'Transfer', 'params': {'deposit': '2000000000000000000000000'}},
      ],
    });
    const usdc = '17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1';
    expect(NearTransaction.ftTransfer(token: usdc, receiverId: 'bob.near', amount: BigInt.from(5000000)).toJson(), {
      'receiverId': usdc,
      'actions': [
        {
          'type': 'FunctionCall',
          'params': {
            'methodName': 'storage_deposit',
            'args': {'account_id': 'bob.near', 'registration_only': true},
            'gas': '30000000000000',
            'deposit': '1250000000000000000000',
          },
        },
        {
          'type': 'FunctionCall',
          'params': {
            'methodName': 'ft_transfer',
            'args': {'receiver_id': 'bob.near', 'amount': '5000000'},
            'gas': '30000000000000',
            'deposit': '1',
          },
        },
      ],
    });
    final wrapped = NearTransaction.ftTransfer(token: 'wrap.near', receiverId: 'bob.near', amount: BigInt.two, wrap: true);
    expect([for (final a in wrapped.actions) (a['params'] as Map)['methodName']], ['storage_deposit', 'near_deposit', 'ft_transfer']);
    expect((wrapped.actions[1]['params'] as Map)['deposit'], '2');
    final vote = NearTransaction.call('pot.sputnik-dao.near', 'act_proposal', {'id': 7, 'action': 'VoteApprove'});
    expect(vote.actions.single, {
      'type': 'FunctionCall',
      'params': {'methodName': 'act_proposal', 'args': {'id': 7, 'action': 'VoteApprove'}, 'gas': '100000000000000', 'deposit': '0'},
    });
  });

  test('signAndSend asks near:signAndSendTransactions; what HOT sent is checked against what was asked', () async {
    final tx = NearTransaction.nearTransfer('bob.near', BigInt.one);
    Map<String, dynamic> outcome({String signer = 'arpit.near', String receiver = 'bob.near', Object? status}) => {
          'status': status ?? {'SuccessValue': ''},
          'transaction': {'hash': '8gA5Xq1k', 'signer_id': signer, 'receiver_id': receiver},
          'transaction_outcome': {'id': '8gA5Xq1k'},
        };
    final fake = _FakeRelay(answers: [{'success': true, 'payload': {'transactions': [outcome()]}}]);
    relayOf(fake);
    final call = await HotWallet.signAndSend([tx]);
    expect(fake.request['method'], 'near:signAndSendTransactions');
    expect(fake.request['request'], {
      'transactions': [
        {'receiverId': 'bob.near', 'actions': [{'type': 'Transfer', 'params': {'deposit': '1'}}]},
      ],
    });
    final sent = (await HotWallet.sent(call, [tx], signer: 'arpit.near')).single;
    expect(sent.hash, '8gA5Xq1k');
    expect(sent.failure, isNull);
    expect(NearSent.explorer(sent.hash), 'https://nearblocks.io/txns/8gA5Xq1k');

    relayOf(_FakeRelay(answers: [{'success': true, 'payload': {'transactions': [outcome(signer: 'mallory.near')]}}]));
    final other = await HotWallet.signAndSend([tx]);
    await expectLater(HotWallet.sent(other, [tx], signer: 'arpit.near'), throwsA(isA<HotError>()));

    relayOf(_FakeRelay(answers: [{'success': true, 'payload': {'transactions': [outcome(status: {'Failure': {'ActionError': {}}})]}}]));
    final failed = await HotWallet.signAndSend([tx]);
    expect((await HotWallet.sent(failed, [tx], signer: 'arpit.near')).single.failure, isNotNull);
  });

  test('NEAR amounts read as NEAR', () {
    expect(HotWallet.format(BigInt.parse('2500000000000000000000000')), '2.5');
    expect(HotWallet.format(BigInt.parse('12345678900000000000000000')), '12.3456');
    expect(HotWallet.format(BigInt.zero), '0');
    expect(HotWallet.isAccount('arpit.near'), isTrue);
    expect(HotWallet.isAccount('606bffe304070f24557a0d5cb8cca57812acfb478b341e9c32e76c68cfcbe48d'), isTrue);
    expect(HotWallet.isAccount('Arpit.near'), isFalse);
  });
}
