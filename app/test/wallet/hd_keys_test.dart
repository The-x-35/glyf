import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/bip39_words.dart';
import 'package:glyf/wallet/hd_keys.dart';
import 'package:web3dart/web3dart.dart' show EthPrivateKey;

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

const abandon = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const legal = 'legal winner thank year wave sausage worth useful legal winner thank yellow';

void main() {
  test('the wordlist is BIP-39\'s English list, byte for byte', () {
    expect(bip39English.length, 2048);
    expect(sha256.convert(utf8.encode('${bip39English.join('\n')}\n')).toString(),
        '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda');
  });

  group('BIP-39 (official vectors, trezor/python-mnemonic vectors.json)', () {
    test('entropy to words', () {
      expect(Bip39.fromEntropy(Uint8List(16)), abandon);
      expect(Bip39.fromEntropy(Uint8List.fromList(List.filled(16, 0x7f))), legal);
      expect(Bip39.fromEntropy(Uint8List.fromList(List.filled(16, 0xff))),
          'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong');
    });

    test('words to seed, with and without a passphrase', () {
      expect(hex(Bip39.seed(abandon, passphrase: 'TREZOR')),
          'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04');
      expect(hex(Bip39.seed(abandon)),
          '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4');
    });

    test('checksums', () {
      expect(Bip39.isValid(abandon), isTrue);
      expect(Bip39.isValid('  Abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon ABOUT '),
          isTrue);
      expect(Bip39.isValid(abandon.replaceFirst('about', 'abandon')), isFalse);
      expect(Bip39.isValid(abandon.replaceFirst('about', 'glyfs')), isFalse);
      expect(Bip39.isValid('abandon abandon'), isFalse);
    });

    test('a new phrase is 24 known words with a good checksum, never the same twice', () {
      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        final p = Bip39.generate();
        expect(p.split(' ').length, 24);
        expect(Bip39.isValid(p), isTrue);
        seen.add(p);
      }
      expect(seen.length, 20);
      // Every byte value can come out of the source (a 0–254 range would
      // skew the words; one popular Dart package does that).
      expect(Bip39.fromEntropy(Uint8List.fromList(List.filled(16, 255))).endsWith('wrong'), isTrue);
      expect(Bip39.generate(random: Random(1)), Bip39.generate(random: Random(1)));
    });
  });

  test('BIP-32 test vector 1 (secp256k1)', () {
    final seed = unhex('000102030405060708090a0b0c0d0e0f');
    expect(hex(Bip32.derive(seed, 'm')), 'e8f32e723decf4051aefac8e2c93c9c5b214313817cdb01a1494b917c8436b35');
    expect(hex(Bip32.derive(seed, "m/0'/1/2'/2/1000000000")),
        '471b76e389e528d6de6d816857e012c5455051cad6660850e58372a6c3e6e7c8');
  });

  test('SLIP-0010 test vector 1 (ed25519)', () {
    final seed = unhex('000102030405060708090a0b0c0d0e0f');
    expect(hex(Slip10.derive(seed, 'm')), '2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7');
    expect(hex(Slip10.derive(seed, "m/0'")), '68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3');
    expect(hex(Slip10.derive(seed, "m/0'/1'/2'/2'/1000000000'")),
        '8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793');
    expect(() => Slip10.derive(seed, 'm/0'), throwsArgumentError);
  });

  group('the addresses MetaMask and Phantom show for a phrase', () {
    // MetaMask's first account for "abandon … about" is the well-known
    // 0x9858EfFD…aA94. The Solana ones were made with ethers 6.13.4 and
    // bip39 3.1.0 + ed25519-hd-key 1.3.0 + tweetnacl 1.0.3 (what Phantom
    // and `solana-keygen recover 'prompt:?key=0/0'` derive).
    test('abandon … about', () {
      final k = PhraseKeys.of(abandon);
      expect(EthPrivateKey(k.evmKey).address.hexEip55, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(k.evmKeyHex, '0x1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727');
      expect(k.solanaAddress, 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk');
      expect(k.solanaSecretBase58,
          '27npWoNE4HfmLeQo1TyWcW7NEA28qnsnDK7kcttDQEWrCWnro83HMJ97rMmpvYYZRwDAvG4KRuB7hTBacvwD7bgi');
    });

    test('legal winner … yellow', () {
      final k = PhraseKeys.of(legal);
      expect(EthPrivateKey(k.evmKey).address.hexEip55, '0x58A57ed9d8d624cBD12e2C467D34787555bB1b25');
      expect(k.solanaAddress, 'BLeUXTx9thHGT7VJUtF9vHEmfMDgW1nnKZ9UVer2CoLX');
    });

    test('the Solana secret is the seed then the public key, 64 bytes', () {
      final k = PhraseKeys.of(abandon);
      final secret = Base58.decode(k.solanaSecretBase58)!;
      expect(secret.length, 64);
      expect(Base58.encode(secret.sublist(32)), k.solanaAddress);
    });
  });
}
