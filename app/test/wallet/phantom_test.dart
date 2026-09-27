import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/phantom.dart';
import 'package:pinenacl/x25519.dart' as nacl;

class _Memory implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> load(String name) async => values[name];
  @override
  Future<void> save(String name, String value) async => values[name] = value;
  @override
  Future<void> clear(String name) async => values.remove(name);
}

/// Phantom's side of the conversation, the way its deeplink demo does it.
class _FakePhantom {
  _FakePhantom() : secret = nacl.PrivateKey.generate();
  final nacl.PrivateKey secret;

  String get publicKey => Base58.encode(secret.publicKey.asTypedList);

  nacl.Box _box(String dappPublic) => nacl.Box(
      myPrivateKey: secret, theirPublicKey: nacl.PublicKey(Base58.decode(dappPublic)!));

  Map<String, String> seal(String dappPublic, Map<String, Object?> json) {
    final sealed = _box(dappPublic).encrypt(Uint8List.fromList(utf8.encode(jsonEncode(json))));
    return {
      'nonce': Base58.encode(sealed.nonce.asTypedList),
      'data': Base58.encode(sealed.cipherText.asTypedList),
    };
  }

  Map<String, dynamic> open(Uri request) {
    final q = request.queryParameters;
    final plain = _box(q['dapp_encryption_public_key']!).decrypt(
        nacl.ByteList(Base58.decode(q['payload']!)!),
        nonce: Base58.decode(q['nonce']!)!);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}

void main() {
  const wallet = '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj';

  test('reads a Connect reply sealed by tweetnacl-js, which Phantom uses', () async {
    // Made with tweetnacl 1.0.3: dapp secret 32 x 0x01, Phantom secret
    // 32 x 0x02, nonce 24 x 0x03, nacl.box.after(reply, nonce, before(...)).
    final store = _Memory()
      ..values['phantom-pending-key'] = '4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi';
    final phantom = Phantom(store);
    final link = await phantom.finishConnect(Uri.parse('glyf://phantom/connect').replace(queryParameters: {
      'phantom_encryption_public_key': 'EuHtd9yCn95edmJqLKFeyXeoPw9nPzp1HTwdJEWEw9YL',
      'nonce': 'GvdqXEAMbSARrubpNP44Vqz4kr6GAxA6',
      'data': '3pzxz1JSxXhEfJh3jP4CsctFa3v92UcakguZfS9631xwPhxukPnAABbEJDy6ptLnbqG6LPHWzSYWQZt76jz1pmRriaZyVSXVVLnjpV3gcgy63YocH7XQ3vR4jptmtucLZU7j',
    }));
    expect(link.address, wallet);
    expect(link.session, 'sess1on');
    expect((await phantom.link())?.address, wallet, reason: 'kept for next time');
    expect(store.values.containsKey('phantom-pending-key'), isFalse);
  });

  test('connects, then Phantom signs exactly the transaction it was sent', () async {
    final store = _Memory();
    final phantom = Phantom(store);
    final fake = _FakePhantom();

    final connect = await phantom.connectUrl();
    expect(connect.toString(), startsWith('https://phantom.app/ul/v1/connect?'));
    expect(connect.queryParameters['redirect_link'], 'glyf://phantom/connect');
    expect(connect.queryParameters['app_url'], 'https://www.tryglyf.com');
    final dappPublic = connect.queryParameters['dapp_encryption_public_key']!;
    await phantom.finishConnect(Uri.parse('glyf://phantom/connect').replace(queryParameters: {
      'phantom_encryption_public_key': fake.publicKey,
      ...fake.seal(dappPublic, {'public_key': wallet, 'session': 'abc'}),
    }));

    final unsigned = Uint8List.fromList(List.generate(200, (i) => i));
    final sign = await phantom.signUrl(unsigned, 'r1');
    expect(sign.path, '/ul/v1/signTransaction');
    expect(sign.queryParameters['redirect_link'], 'glyf://phantom/sign/r1');
    final asked = fake.open(sign);
    expect(asked['session'], 'abc');
    expect(Base58.decode(asked['transaction'] as String), unsigned);

    final signed = Uint8List.fromList([...unsigned.reversed]);
    final back = await phantom.finishSign(Uri.parse('glyf://phantom/sign/r1').replace(
        queryParameters: fake.seal(dappPublic, {'transaction': Base58.encode(signed)})));
    expect(back, signed);
  });

  test('Cancel in Phantom comes back as a cancelled error', () async {
    final phantom = Phantom(_Memory());
    await expectLater(
        phantom.finishSign(Uri.parse('glyf://phantom/sign/r1?errorCode=4001&errorMessage=User%20rejected')),
        throwsA(isA<PhantomError>().having((e) => e.cancelled, 'cancelled', isTrue)));
  });

  test('a reply that was tampered with is refused', () async {
    final store = _Memory();
    final phantom = Phantom(store);
    final fake = _FakePhantom();
    final connect = await phantom.connectUrl();
    final sealed = fake.seal(connect.queryParameters['dapp_encryption_public_key']!, {'public_key': wallet, 'session': 's'});
    final bad = Base58.decode(sealed['data']!)!..[5] ^= 1;
    await expectLater(
        phantom.finishConnect(Uri.parse('glyf://phantom/connect').replace(queryParameters: {
          'phantom_encryption_public_key': fake.publicKey,
          'nonce': sealed['nonce']!,
          'data': Base58.encode(bad),
        })),
        throwsA(isA<PhantomError>()));
    expect(await phantom.link(), isNull);
  });
}
