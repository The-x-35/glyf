import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/flash_solana.dart';
import 'package:glyf/wallet/phantom.dart';
import 'package:glyf/wallet/solana.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as nacl;

// Vectors made with @solana/web3.js 1.98.0 and tweetnacl 1.0.3
// (Keypair.fromSeed(32 x 0x07)): a Flash stop-loss quote's setup for a
// fresh wallet selling native SOL — the USDC account, the wrap, the
// delegation — built with new Transaction().add(...) and signed.
const _funder = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _blockhash = '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd';
const _quoteJson = r'''{"svm": {"ataSetupIxs": [{"programId": "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL", "accounts": [{"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": true, "isWritable": true}, {"pubkey": "7woc3ajaGMMXczFYjxon4aQoHH3j126fMUR9c58eHRsK", "isSigner": false, "isWritable": true}, {"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": false, "isWritable": false}, {"pubkey": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "isSigner": false, "isWritable": false}, {"pubkey": "11111111111111111111111111111111", "isSigner": false, "isWritable": false}, {"pubkey": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "isSigner": false, "isWritable": false}], "data": "2"}], "delegateIx": {"programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "accounts": [{"pubkey": "59btS1MqkxUBx9sHGorTuLAHMbCzzJmjagXiEac3Mtb2", "isSigner": false, "isWritable": true}, {"pubkey": "3jBWeQrnfEhw5LY53hwcoYKQJsrTUbtLbmGrNYCr1Fiq", "isSigner": false, "isWritable": false}, {"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": true, "isWritable": false}], "data": "4h6bzpF8MKT4"}, "sponsoredDelegateTx": null, "orderMessage": "DFS|m=So11111111111111111111111111111111111111112|t=100000000|h=FmUTW5JA5S4Y71sibJaYv2", "nonce": "642167567179317251", "deadline": "281474976710655"}, "wrap": {"svmInstructions": [{"programId": "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL", "accounts": [{"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": true, "isWritable": true}, {"pubkey": "59btS1MqkxUBx9sHGorTuLAHMbCzzJmjagXiEac3Mtb2", "isSigner": false, "isWritable": true}, {"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": false, "isWritable": false}, {"pubkey": "So11111111111111111111111111111111111111112", "isSigner": false, "isWritable": false}, {"pubkey": "11111111111111111111111111111111", "isSigner": false, "isWritable": false}, {"pubkey": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "isSigner": false, "isWritable": false}], "data": "2"}, {"programId": "11111111111111111111111111111111", "accounts": [{"pubkey": "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB", "isSigner": true, "isWritable": true}, {"pubkey": "59btS1MqkxUBx9sHGorTuLAHMbCzzJmjagXiEac3Mtb2", "isSigner": false, "isWritable": true}], "data": "3Bxs411Dtc7pkFQj"}, {"programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "accounts": [{"pubkey": "59btS1MqkxUBx9sHGorTuLAHMbCzzJmjagXiEac3Mtb2", "isSigner": false, "isWritable": true}], "data": "J"}]}}''';
const _unsigned = 'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAYJ6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iw9otc7EHXqRBVUKP/hJrStF8cQ0CEHERIHPlFAZ4OPwWcwLkkYlNdJLqa+T5FOpPRfoULmRYZ8kWSidtXddvB2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAohacdqZxrs9jfOU7/ppfAQLLgqtQMFRwRrxlkLmZUooyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZxvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWEGm4hX/quBhPtof2NGGMA12sQ53BrrO1WYoPAAAAAAAQbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpNakm8uOUOZEr8Ha85ELeUSXlVK1iceTS0wTbatZLj+wFBQYAAgAGAwgBAQUGAAEABwMIAQEDAgABDAIAAAAA4fUFAAAAAAgBAQERCAMBBAAJBP//////////';
const _signed = 'AZpCWeL+JtO72yJ/ZNjfaz0HVALyecKW0OAUi3EfqNmTHrZHka5qpxfpElXZJvcSyGsORIhR3xjIi4uGvuZ4oAgBAAYJ6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iw9otc7EHXqRBVUKP/hJrStF8cQ0CEHERIHPlFAZ4OPwWcwLkkYlNdJLqa+T5FOpPRfoULmRYZ8kWSidtXddvB2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAohacdqZxrs9jfOU7/ppfAQLLgqtQMFRwRrxlkLmZUooyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZxvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWEGm4hX/quBhPtof2NGGMA12sQ53BrrO1WYoPAAAAAAAQbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpNakm8uOUOZEr8Ha85ELeUSXlVK1iceTS0wTbatZLj+wFBQYAAgAGAwgBAQUGAAEABwMIAQEDAgABDAIAAAAA4fUFAAAAAAgBAQERCAMBBAAJBP//////////';
const _messageSignature = 'ndFhGM3zrqx1TTMiE2YrWS5KtmegWLA8WkeTSJNLTvMsrxR6EYLdSYjSSY3nbAeEcJK29JxohRTLh53DWuqNEPh';

class _Memory implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> load(String name) async => values[name];
  @override
  Future<void> save(String name, String value) async => values[name] = value;
  @override
  Future<void> clear(String name) async => values.remove(name);
}

void main() {
  final quote = jsonDecode(_quoteJson) as Map<String, dynamic>;
  final signer = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 7)));

  Uint8List sign(Uint8List unsigned) {
    final parts = FlashSvm.split(unsigned)!;
    final sig = signer.sign(parts.message).signature.asTypedList;
    return Uint8List.fromList([...unsigned.sublist(0, 1), ...sig, ...parts.message]);
  }

  test('the test key is the funder', () {
    expect(Base58.encode(signer.verifyKey.asTypedList), _funder);
  });

  test('setup instructions come in Flash\'s order: accounts, wrap, delegation', () {
    final ixs = FlashSvm.setupInstructions(quote);
    expect(ixs.map((i) => i.program).toList(), [
      Sol.ataProgram, Sol.ataProgram, Sol.systemProgram, Sol.tokenProgram, Sol.tokenProgram,
    ]);
    expect(ixs.last.data.first, 4, reason: 'SPL Approve last');
    // The account Flash names is the one the phone derives.
    expect(ixs.first.accounts[1].address, Sol.tokenAccount(_funder, Sol.usdc));
  });

  test('builds the setup transaction web3.js does (its accounts in first-seen order, web3.js sorts them)', () {
    final tx = FlashSvm.setupTransaction(quote: quote, funder: _funder, blockhash: _blockhash)!;
    final ours = Sol.decodeLegacy(tx)!, theirs = Sol.decodeLegacy(base64.decode(_unsigned))!;
    expect(ours.feePayer, theirs.feePayer);
    expect(ours.blockhash, _blockhash);
    expect(ours.instructions.length, theirs.instructions.length);
    for (var k = 0; k < ours.instructions.length; k++) {
      final a = ours.instructions[k], b = theirs.instructions[k];
      expect(a.program, b.program);
      expect(a.data, b.data);
      expect([for (final m in a.accounts) '${m.address}:${m.signer}:${m.writable}'],
          [for (final m in b.accounts) '${m.address}:${m.signer}:${m.writable}']);
    }
    expect(tx.length, base64.decode(_unsigned).length);
    // web3.js's signed one is the same setup, so the phone takes it.
    expect(FlashSvm.isSignedSetup(base64.decode(_signed), tx, _funder), isTrue);
    expect(FlashSvm.isSignedSetup(sign(tx), tx, _funder), isTrue);
  });

  test('a quote with nothing to set up needs no transaction', () {
    expect(FlashSvm.setupTransaction(quote: {'svm': {'ataSetupIxs': null, 'delegateIx': null}, 'wrap': null},
        funder: _funder, blockhash: _blockhash), isNull);
  });

  test('the attached pair\'s delegation goes after the entry\'s', () {
    final pairDelegate = Map<String, dynamic>.from(quote['svm']['delegateIx'] as Map);
    final withPair = {...quote, 'attachedBracket': {'svm': {'orderMessage': 'x', 'nonce': '1', 'delegateIx': pairDelegate}}};
    expect(FlashSvm.setupInstructions(withPair).length, 6);
  });

  test('refuses an instruction that wants someone else\'s signature', () {
    final odd = jsonDecode(_quoteJson) as Map<String, dynamic>;
    (((odd['svm'] as Map)['delegateIx'] as Map)['accounts'] as List)[1]['isSigner'] = true;
    expect(() => FlashSvm.setupTransaction(quote: odd, funder: _funder, blockhash: _blockhash),
        throwsA(isA<FormatException>()));
  });

  test('takes a blockhash out of Flash\'s own setup transaction', () {
    expect(FlashSvm.blockhashOf({'setupTxs': [_unsigned]}), _blockhash);
    expect(FlashSvm.blockhashOf({'setupTxs': null}), isNull);
  });

  group('Phantom\'s signed setup', () {
    final asked = base64.decode(_unsigned);

    test('is accepted when it is what was asked, signed by the funder', () {
      expect(FlashSvm.isSignedSetup(sign(asked), asked, _funder), isTrue);
      expect(FlashSvm.txSignature(sign(asked)), isNotNull);
    });

    test('is accepted with Phantom\'s priority fee added in front', () {
      final decoded = Sol.decodeLegacy(asked)!;
      final withFee = Sol.compileLegacy(feePayer: _funder, blockhash: '11111111111111111111111111111112', instructions: [
        const Instruction(FlashSvm.computeBudgetProgram, [], [3, 1, 0, 0, 0, 0, 0, 0, 0]),
        ...FlashSvm.setupInstructions(quote),
      ]);
      expect(decoded.instructions.length, 5);
      expect(FlashSvm.isSignedSetup(sign(withFee), asked, _funder), isTrue);
    });

    test('is refused unsigned, signed by another key, or changed', () {
      expect(FlashSvm.isSignedSetup(asked, asked, _funder), isFalse);
      final other = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 9)));
      final parts = FlashSvm.split(asked)!;
      final wrongKey = Uint8List.fromList(
          [1, ...other.sign(parts.message).signature.asTypedList, ...parts.message]);
      expect(FlashSvm.isSignedSetup(wrongKey, asked, _funder), isFalse);
      // The same instructions bar the delegate: another address takes it.
      final changed = Sol.compileLegacy(feePayer: _funder, blockhash: _blockhash, instructions: [
        ...FlashSvm.setupInstructions(quote).take(4),
        Instruction(Sol.tokenProgram, [
          AccountMeta(Sol.tokenAccount(_funder, Sol.wsol), writable: true),
          const AccountMeta('7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj'),
          AccountMeta(_funder, signer: true),
        ], [4, 255, 255, 255, 255, 255, 255, 255, 255]),
      ]);
      expect(FlashSvm.isSignedSetup(sign(changed), asked, _funder), isFalse);
    });
  });

  group('order message', () {
    final message = (quote['svm'] as Map)['orderMessage'] as String;

    test('reads Flash\'s format', () {
      final m = FlashOrderMessage.parse(message)!;
      expect(m.mint, Sol.wsol);
      expect(m.total, BigInt.from(100000000));
      expect(FlashOrderMessage.parse('hello'), isNull);
    });

    test('must spend the coin and the amount asked for', () {
      expect(FlashSvm.messageProblem(message, mint: Sol.wsol, total: Sol.units('0.1', 9)), isNull);
      expect(FlashSvm.messageProblem(message, mint: Sol.wsol), isNull);
      expect(FlashSvm.messageProblem(message, mint: Sol.usdc, total: Sol.units('0.1', 9)), isNotNull);
      expect(FlashSvm.messageProblem(message, mint: Sol.wsol, total: Sol.units('1', 9)), isNotNull);
      expect(FlashSvm.messageProblem(null, mint: Sol.wsol), isNotNull);
    });

    test('a signature from tweetnacl (what Phantom uses) checks out', () {
      final sig = Base58.decode(_messageSignature)!;
      expect(FlashSvm.verifyMessage(message, sig, _funder), isTrue);
      expect(FlashSvm.verifyMessage('${message}x', sig, _funder), isFalse);
      expect(FlashSvm.verifyMessage(message, sig, '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj'), isFalse);
      expect(FlashSvm.verifyMessage(message, Uint8List(64), _funder), isFalse);
    });
  });

  group('sponsored delegation', () {
    test('is accepted with the funder\'s signature in its slot, the message unchanged', () {
      // Sponsor pays (slot 0), the funder signs too (slot 1).
      const sponsor = '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj';
      final ix = FlashSvm.setupInstructions(quote).last;
      final asked = Sol.compileLegacy(feePayer: sponsor, blockhash: _blockhash, instructions: [ix]);
      expect(asked[0], 2);
      final parts = FlashSvm.split(asked)!;
      final sig = signer.sign(parts.message).signature.asTypedList;
      final signed = Uint8List.fromList([2, ...List.filled(64, 0), ...sig, ...parts.message]);
      expect(FlashSvm.isSignedSponsored(signed, asked, _funder), isTrue);
      final wrongSlot = Uint8List.fromList([2, ...sig, ...List.filled(64, 0), ...parts.message]);
      expect(FlashSvm.isSignedSponsored(wrongSlot, asked, _funder), isFalse);
      expect(FlashSvm.isSignedSponsored(asked, asked, _funder), isFalse);
    });
  });

  group('PhantomRequests', () {
    test('hands a trade\'s reply to the trade waiting on it', () async {
      final id = PhantomRequests.newId();
      final reply = Uri.parse('glyf://phantom/trade/$id?nonce=a&data=b');
      final got = await PhantomRequests.ask(id, () async {
        expect(PhantomRequests.handle(reply), isTrue);
        return null;
      });
      expect(got, reply);
      expect(PhantomRequests.isWaiting(id), isFalse);
      // Nobody waits any more: the pay screen gets it ("Nothing to finish").
      expect(PhantomRequests.handle(reply), isFalse);
    });

    test('leaves pay and connect replies alone', () async {
      final id = PhantomRequests.newId();
      final waiting = PhantomRequests.ask(id, () async => null, timeout: const Duration(seconds: 2));
      expect(PhantomRequests.handle(Uri.parse('glyf://phantom/sign/$id')), isFalse);
      expect(PhantomRequests.handle(Uri.parse('glyf://phantom/connect?x=1')), isFalse);
      expect(PhantomRequests.handle(Uri.parse('glyf://mmsdk/trade/$id')), isFalse);
      expect(PhantomRequests.handle(Uri.parse('glyf://phantom/trade/someone-else')), isFalse);
      expect(PhantomRequests.isWaiting(id), isTrue);
      PhantomRequests.handle(Uri.parse('glyf://phantom/trade/$id'));
      await waiting;
    });

    test('says when Phantom could not be opened', () async {
      final id = PhantomRequests.newId();
      await expectLater(PhantomRequests.ask(id, () async => 'Install Phantom, then try again'),
          throwsA(isA<PhantomUnavailable>()));
      expect(PhantomRequests.isWaiting(id), isFalse);
    });
  });

  test('Phantom signMessage: the request carries the UTF-8 text, the reply its signature', () async {
    final phantomSecret = nacl.PrivateKey.generate();
    final dapp = nacl.PrivateKey.generate();
    final store = _Memory()
      ..values['phantom-link'] = jsonEncode(PhantomLink(
        address: _funder,
        session: 'fake-session',
        dappSecret: Base58.encode(dapp.asTypedList),
        phantomKey: Base58.encode(phantomSecret.publicKey.asTypedList),
      ).toJson());
    final phantom = Phantom(store);
    const message = 'DFS|m=So11111111111111111111111111111111111111112|t=1|h=abc';
    final url = await phantom.signMessageUrl(message, 'id1');
    expect(url.path, '/ul/v1/signMessage');
    expect(url.queryParameters['redirect_link'], 'glyf://phantom/trade/id1');
    final box = nacl.Box(myPrivateKey: phantomSecret, theirPublicKey: dapp.publicKey);
    final payload = jsonDecode(utf8.decode(box.decrypt(nacl.ByteList(Base58.decode(url.queryParameters['payload']!)!),
        nonce: Base58.decode(url.queryParameters['nonce']!)!))) as Map;
    expect(utf8.decode(Base58.decode(payload['message'] as String)!), message);
    expect(payload['session'], 'fake-session');
    expect(payload['display'], 'utf8');
    final sig = signer.sign(Uint8List.fromList(utf8.encode(message))).signature.asTypedList;
    final sealed = box.encrypt(Uint8List.fromList(utf8.encode(jsonEncode({'signature': Base58.encode(sig)}))));
    final reply = Uri.parse('glyf://phantom/trade/id1').replace(queryParameters: {
      'nonce': Base58.encode(sealed.nonce.asTypedList),
      'data': Base58.encode(sealed.cipherText.asTypedList),
    });
    final got = await phantom.finishSignMessage(reply);
    expect(FlashSvm.verifyMessage(message, got, _funder), isTrue);
    await expectLater(phantom.finishSignMessage(Uri.parse('glyf://phantom/trade/id1?errorCode=4001&errorMessage=no')),
        throwsA(isA<PhantomError>().having((e) => e.cancelled, 'cancelled', true)));
  });
}
