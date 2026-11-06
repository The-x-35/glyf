import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:web3dart/web3dart.dart' show EthPrivateKey;

import '../core/bridge.dart';
import 'flash_solana.dart';
import 'hd_keys.dart';

/// The Glyf wallet's secrets, on this phone only (the Keychain through the
/// bridge, the same store as the Phantom session; never in shared settings,
/// never sent, never logged).
///
/// Since 2026-11-06 a Glyf wallet is a 24-word recovery phrase, and both of
/// its addresses come from it the way MetaMask (Ethereum) and Phantom
/// (Solana) derive theirs, so the words open the same wallet there.
/// Wallets made before that are one random Ethereum key (`evm-key`): that
/// key keeps its address and stays exportable. Switching such a wallet to a
/// phrase adds the phrase and leaves the old key where it is, so its address
/// is still reachable by its private key; nothing is ever deleted here.
abstract final class GlyfKeys {
  static const phraseName = 'glyf-phrase';

  /// The random Ethereum key every Glyf wallet was before phrases.
  static const legacyName = 'evm-key';

  static PhraseKeys? _phrase;
  static EthPrivateKey? _legacy;
  static bool _loaded = false;

  /// The Ethereum address that signs (the phrase's, else the old key's).
  static final evmAddress = ValueNotifier<String?>(null);

  /// The Solana address; only a phrase wallet has one.
  static final solanaAddress = ValueNotifier<String?>(null);

  /// The pre-phrase key's address, while a phrase wallet also holds one.
  static final oldEvmAddress = ValueNotifier<String?>(null);

  static bool get hasPhrase => _phrase != null;

  /// A wallet made before recovery phrases: one Ethereum key, no Solana.
  static bool get isLegacyOnly => _phrase == null && _legacy != null;

  static bool get exists => _phrase != null || _legacy != null;

  /// Reads what this phone holds; makes nothing.
  static Future<void> load() => _loading ??= _load().whenComplete(() => _loading = null);

  static Future<void>? _loading;

  static Future<void> _load() async {
    if (_loaded) return;
    final phrase = await GlyfBridge.walletSecretLoad(phraseName);
    final legacy = await GlyfBridge.walletSecretLoad(legacyName);
    _phrase = phrase == null || !Bip39.isValid(phrase) ? null : await _derive(phrase);
    _legacy = legacy == null || legacy.isEmpty ? null : EthPrivateKey.fromHex(legacy);
    _loaded = true;
    _publish();
  }

  /// A new phrase wallet when there is no wallet at all. An existing
  /// wallet (phrase or old key) is never replaced here.
  static Future<void> ensure() async {
    await load();
    if (exists) return;
    await _savePhrase(Bip39.generate());
  }

  /// An old-key wallet gets a phrase wallet of its own; the old key stays
  /// saved under its own name and keeps its address (oldEvmAddress).
  static Future<void> switchToPhrase() async {
    await load();
    if (_phrase != null) return;
    await _savePhrase(Bip39.generate());
  }

  static Future<void> _savePhrase(String phrase) async {
    await GlyfBridge.walletSecretSave(phraseName, phrase);
    // Read back before it counts: a phrase that didn't save would be a
    // wallet nobody can restore.
    final saved = await GlyfBridge.walletSecretLoad(phraseName);
    if (saved != phrase) throw StateError('The Keychain didn’t keep the wallet');
    _phrase = await _derive(phrase);
    _publish();
  }

  /// PBKDF2's 2048 rounds off the UI thread.
  static Future<PhraseKeys> _derive(String phrase) async {
    final parts = await compute(_deriveRaw, phrase);
    return PhraseKeys.fromParts(parts.$1, parts.$2);
  }

  static (Uint8List, Uint8List) _deriveRaw(String phrase) {
    final k = PhraseKeys.of(phrase);
    return (k.evmKey, k.solanaSeed);
  }

  static void _publish() {
    final p = _phrase, l = _legacy;
    evmAddress.value = p != null
        ? EthPrivateKey(p.evmKey).address.hexEip55
        : l?.address.hexEip55;
    solanaAddress.value = p?.solanaAddress;
    oldEvmAddress.value = p != null ? l?.address.hexEip55 : null;
  }

  /// The key that signs Ethereum transactions.
  static EthPrivateKey? get evmKey => _phrase == null ? _legacy : EthPrivateKey(_phrase!.evmKey);

  /// The key that signs Solana transactions and messages.
  static ed.SigningKey? get solanaSigner => _phrase?.solanaSigner;

  // What the Wallet screen reveals, after the phone's own unlock.

  static Future<String?> phrase() => GlyfBridge.walletSecretLoad(phraseName);

  static String? get evmKeyHex => evmKey == null ? null : _hex(evmKey!);

  static String? get oldEvmKeyHex => _phrase != null && _legacy != null ? _hex(_legacy!) : null;

  static String? get solanaSecret => _phrase?.solanaSecretBase58;

  static String _hex(EthPrivateKey k) => '0x${k.privateKeyInt.toRadixString(16).padLeft(64, '0')}';

  /// Forgets what's in memory (not the Keychain): tests start over.
  static void reset() {
    _phrase = null;
    _legacy = null;
    _loaded = false;
    _loading = null;
    _publish();
  }
}

/// Signing a Solana transaction or message with a key on this phone (the
/// Glyf wallet's), the same bytes a wallet app would sign.
abstract final class SolanaSigning {
  /// [tx] (serialized, legacy or v0, signatures unfilled or not) with
  /// [key]'s signature in its own slot among the signers; null when [key]
  /// isn't one of them.
  static Uint8List? signTransaction(Uint8List tx, ed.SigningKey key) {
    final parts = FlashSvm.split(tx);
    if (parts == null) return null;
    final slot = FlashSvm.signerSlot(parts.message, key.verifyKey.asTypedList);
    if (slot == null || slot >= parts.signatures.length) return null;
    final signature = key.sign(parts.message).signature.asTypedList;
    final out = Uint8List.fromList(tx);
    // The signatures sit right after their compact-u16 count.
    final start = tx.length - parts.message.length - 64 * parts.signatures.length;
    out.setRange(start + 64 * slot, start + 64 * slot + 64, signature);
    return out;
  }

  /// An ed25519 signature over [message], 64 bytes.
  static Uint8List signMessage(List<int> message, ed.SigningKey key) =>
      Uint8List.fromList(key.sign(Uint8List.fromList(message)).signature.asTypedList);
}
