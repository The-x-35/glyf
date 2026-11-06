import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'base58.dart';
import 'bip39_words.dart';

/// A recovery phrase (BIP-39) and the two keys Glyf makes from it, the
/// way MetaMask and Phantom do, so the same 24 words open the same
/// addresses there:
/// - Ethereum: BIP-32 secp256k1 at m/44'/60'/0'/0/0 (MetaMask's first account)
/// - Solana: SLIP-0010 ed25519 at m/44'/501'/0'/0' (Phantom's first account)
/// Pure code, no I/O: the phrase itself lives in the Keychain (GlyfKeys).
abstract final class Bip39 {
  static const words = bip39English;

  /// 24 new words from 256 bits of the system's secure random source
  /// (Arpit, 2026-11-06: "we will have a 24 words seed phrase").
  static String generate({Random? random}) {
    final r = random ?? Random.secure();
    return fromEntropy(Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))));
  }

  /// [entropy] (16–32 bytes, a multiple of 4) as words: its bits and the
  /// first ENT/32 bits of its SHA-256, 11 bits a word.
  static String fromEntropy(Uint8List entropy) {
    if (entropy.length < 16 || entropy.length > 32 || entropy.length % 4 != 0) {
      throw ArgumentError('entropy must be 16–32 bytes, a multiple of 4');
    }
    final bits = StringBuffer();
    for (final b in entropy) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    final hash = c.sha256.convert(entropy).bytes;
    final cs = entropy.length * 8 ~/ 32;
    bits.write(hash.map((b) => b.toRadixString(2).padLeft(8, '0')).join().substring(0, cs));
    final all = bits.toString();
    return [
      for (var i = 0; i < all.length; i += 11) words[int.parse(all.substring(i, i + 11), radix: 2)],
    ].join(' ');
  }

  /// The words as one normalised phrase: lower case, single spaces.
  static String normalise(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

  /// Whether [phrase] is 12–24 known words with the right checksum.
  static bool isValid(String phrase) {
    final list = normalise(phrase).split(' ');
    if (list.length < 12 || list.length > 24 || list.length % 3 != 0) return false;
    final bits = StringBuffer();
    for (final w in list) {
      final i = _index[w];
      if (i == null) return false;
      bits.write(i.toRadixString(2).padLeft(11, '0'));
    }
    final all = bits.toString();
    final cs = all.length ~/ 33;
    final entBits = all.substring(0, all.length - cs);
    final entropy = Uint8List.fromList([
      for (var i = 0; i < entBits.length; i += 8) int.parse(entBits.substring(i, i + 8), radix: 2),
    ]);
    final hash = c.sha256.convert(entropy).bytes;
    final want = hash.map((b) => b.toRadixString(2).padLeft(8, '0')).join().substring(0, cs);
    return want == all.substring(all.length - cs);
  }

  static final Map<String, int> _index = {for (var i = 0; i < words.length; i++) words[i]: i};

  /// The 64-byte seed: PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" +
  /// passphrase (Glyf uses none, as MetaMask and Phantom don't by default).
  static Uint8List seed(String phrase, {String passphrase = ''}) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128))
      ..init(Pbkdf2Parameters(Uint8List.fromList(utf8.encode('mnemonic$passphrase')), 2048, 64));
    return kdf.process(Uint8List.fromList(utf8.encode(normalise(phrase))));
  }
}

/// A derivation path as indexes, hardened ones with the top bit set.
List<int> _path(String path) {
  final parts = path.split('/');
  if (parts.isEmpty || parts.first != 'm') throw ArgumentError('a path starts with m');
  return [
    for (final p in parts.skip(1))
      p.endsWith("'") ? (int.parse(p.substring(0, p.length - 1)) | 0x80000000) : int.parse(p),
  ];
}

Uint8List _hmac512(List<int> key, List<int> data) => Uint8List.fromList(c.Hmac(c.sha512, key).convert(data).bytes);

Uint8List _u32(int i) => Uint8List(4)..buffer.asByteData().setUint32(0, i);

BigInt _int(List<int> b) => BigInt.parse(b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

Uint8List _bytes32(BigInt v) {
  final hex = v.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

/// BIP-32 on secp256k1, private derivation only.
abstract final class Bip32 {
  static final _curve = ECCurve_secp256k1();

  /// The 32-byte private key at [path] under [seed].
  static Uint8List derive(Uint8List seed, String path) {
    var i = _hmac512(utf8.encode('Bitcoin seed'), seed);
    var key = _int(i.sublist(0, 32));
    var chain = i.sublist(32);
    final n = _curve.n;
    for (final index in _path(path)) {
      final data = index & 0x80000000 != 0
          ? [0, ..._bytes32(key), ..._u32(index)]
          : [..._publicKey(key), ..._u32(index)];
      i = _hmac512(chain, data);
      final tweak = _int(i.sublist(0, 32));
      // A tweak at or past n, or a zero key, is skipped to the next index by
      // BIP-32; the odds are below 1 in 2^127, so it is refused instead.
      if (tweak >= n) throw StateError('invalid child key');
      key = (tweak + key) % n;
      if (key == BigInt.zero) throw StateError('invalid child key');
      chain = i.sublist(32);
    }
    return _bytes32(key);
  }

  /// The compressed public key (33 bytes).
  static Uint8List _publicKey(BigInt key) => (_curve.G * key)!.getEncoded(true);
}

/// SLIP-0010 on ed25519: every step hardened.
abstract final class Slip10 {
  /// The 32-byte ed25519 seed at [path] under [seed].
  static Uint8List derive(Uint8List seed, String path) {
    var i = _hmac512(utf8.encode('ed25519 seed'), seed);
    var key = i.sublist(0, 32);
    var chain = i.sublist(32);
    for (final index in _path(path)) {
      if (index & 0x80000000 == 0) throw ArgumentError('ed25519 derives hardened steps only');
      i = _hmac512(chain, [0, ...key, ..._u32(index)]);
      key = i.sublist(0, 32);
      chain = i.sublist(32);
    }
    return key;
  }
}

/// The keys a phrase opens, as MetaMask and Phantom read it.
class PhraseKeys {
  PhraseKeys._(this.evmKey, this.solanaSeed);

  static const evmPath = "m/44'/60'/0'/0/0";
  static const solanaPath = "m/44'/501'/0'/0'";

  factory PhraseKeys.of(String phrase) {
    final seed = Bip39.seed(phrase);
    return PhraseKeys._(Bip32.derive(seed, evmPath), Slip10.derive(seed, solanaPath));
  }

  /// Keys already derived (in another isolate).
  factory PhraseKeys.fromParts(Uint8List evmKey, Uint8List solanaSeed) => PhraseKeys._(evmKey, solanaSeed);

  /// The Ethereum private key, 32 bytes.
  final Uint8List evmKey;

  /// The Solana key's 32-byte ed25519 seed.
  final Uint8List solanaSeed;

  String get evmKeyHex => '0x${evmKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  late final ed.SigningKey solanaSigner = ed.SigningKey.fromSeed(solanaSeed);

  String get solanaAddress => Base58.encode(solanaSigner.verifyKey.asTypedList);

  /// The 64-byte secret (seed, then public key) in base58: what Phantom's
  /// "Import private key" and solana-keygen's keypair take.
  String get solanaSecretBase58 => Base58.encode(Uint8List.fromList([...solanaSeed, ...solanaSigner.verifyKey.asTypedList]));
}
