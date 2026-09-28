import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/phantom.dart';
import 'package:glyf/wallet/wallet_flow.dart';
import 'package:pinenacl/x25519.dart' as nacl;

/// Phantom's signed payment goes on to Solana through Glyf's server. What
/// the person is told when that server misbehaves decides whether they
/// pay twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  const wallet = '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj';
  final dapp = nacl.PrivateKey.generate();
  final phantom = nacl.PrivateKey.generate();

  late HttpServer server;
  late Map<String, String> secrets;
  late Map<String, dynamic> settings;

  /// Each RPC method's answer; one that isn't listed gets a proxy's HTML 502.
  var rpc = <String, Object>{};

  setUp(() async {
    // Real sockets, to the stand-in server below.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final answer = req.uri.path == '/wallet/rpc' ? rpc[(jsonDecode(body) as Map)['method']] : const {};
      if (answer == null) {
        req.response
          ..statusCode = 502
          ..headers.contentType = ContentType.html
          ..write('<html><body>502 Bad Gateway</body></html>');
      } else {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(answer));
      }
      await req.response.close();
    });
    secrets = {
      'phantom-link': jsonEncode(PhantomLink(
        address: wallet,
        session: 's',
        dappSecret: Base58.encode(dapp.asTypedList),
        phantomKey: Base58.encode(phantom.publicKey.asTypedList),
      ).toJson()),
      'phantom-pending-pay':
          jsonEncode(const PendingPay(id: 'r1', kind: PayKind.send, summary: '5 USDC to 7dHb…7ARj').toJson()),
    };
    settings = {'backendURL': 'http://127.0.0.1:${server.port}'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'walletSecretLoad':
          return secrets[args['name']];
        case 'walletSecretClear':
          secrets.remove(args['name']);
          return true;
        case 'readSharedSettings':
          return jsonEncode(settings);
        case 'writeSharedSettings':
          settings = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
    await server.close(force: true);
  });

  /// Phantom's reply: the transaction, signed, sealed for Glyf.
  Uri signedReply(String id) {
    final sealed = nacl.Box(myPrivateKey: phantom, theirPublicKey: dapp.publicKey).encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode({'transaction': Base58.encode(List.filled(100, 7))}))));
    return Uri.parse('glyf://phantom/sign/$id').replace(queryParameters: {
      'nonce': Base58.encode(sealed.nonce.asTypedList),
      'data': Base58.encode(sealed.cipherText.asTypedList),
    });
  }

  test('a payment that reached Solana is reported submitted, with its link, when the check on it breaks', () async {
    // Sent fine; the status check then gets a 502 page, not JSON.
    rpc = {'sendTransaction': {'result': 'SIG1'}};
    final outcomes = await WalletFlow.handleReply(signedReply('r1')).toList();

    expect(outcomes.first.state, PayState.working);
    expect(outcomes.last.state, PayState.submitted);
    expect(outcomes.last.title, isNot(contains('go through')));
    expect(outcomes.last.signature, 'SIG1');
    final told = jsonDecode(settings['walletOutcome'] as String) as Map;
    expect(told['title'], 'Submitted');
    expect(told['detail'], contains('https://solscan.io/tx/SIG1'));
    expect(secrets.containsKey('phantom-pending-pay'), isFalse, reason: 'a reply is never sent on twice');
  });

  test('a send answered with an HTML page ends in an answer, not a spinner, and no "try again"', () async {
    rpc = {};
    final outcomes = await WalletFlow.handleReply(signedReply('r1')).toList();

    // It may have reached Solana: the transaction's own signature is the
    // way to look, never "Try again", which could pay twice.
    expect(outcomes.last.state, PayState.submitted);
    expect(outcomes.last.signature, isNotNull);
    expect(outcomes.last.detail, contains('not confirmed yet'));
  });

  test('a reply Glyf never asked for still ends the screen', () async {
    final outcomes = await WalletFlow.handleReply(Uri.parse('glyf://phantom/disconnect')).toList();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.state, isNot(PayState.working));
  });

  test('a signed transaction names itself: its first signature, in base58', () {
    final sig = List<int>.generate(64, (i) => i + 1);
    final signed = Uint8List.fromList([1, ...sig, 9, 9, 9]);
    expect(WalletFlow.txSignature(signed), Base58.encode(sig));
    expect(WalletFlow.txSignature(Uint8List.fromList([0, ...sig, 1])), isNull, reason: 'no signature');
    expect(WalletFlow.txSignature(Uint8List(10)), isNull, reason: 'too short');
  });
}
