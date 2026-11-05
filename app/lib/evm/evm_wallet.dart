import 'dart:convert';
import 'dart:math';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/foundation.dart';
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes, keccak256;
import 'package:web3dart/web3dart.dart';

import '../core/bridge.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';

/// Glyf's own Ethereum wallet: one key, made on this phone and sealed in
/// the Keychain (the same store as the Phantom session). Glyf's servers never
/// see it. It signs swaps, Flash orders, Whitechain requests and the Arkiv
/// vault backup on every EVM chain Glyf knows, because a keyboard can't hold
/// a WalletConnect session and the simulator has no wallet app to hand off to.
abstract final class EvmWallet {
  static const _keyName = 'evm-key';

  static EthPrivateKey? _key;

  /// The wallet's address once it exists, checksummed.
  static final address = ValueNotifier<String?>(null);

  /// Loads the key if one was made before; never makes one.
  static Future<String?> load() async {
    if (_key != null) return address.value;
    final hex = await GlyfBridge.walletSecretLoad(_keyName);
    if (hex == null || hex.isEmpty) return null;
    _key = EthPrivateKey.fromHex(hex);
    address.value = _key!.address.hexEip55;
    await _share();
    return address.value;
  }

  /// The wallet, made the first time it's asked for.
  static Future<String> ensure() async {
    final existing = await load();
    if (existing != null) return existing;
    final key = EthPrivateKey.createRandom(Random.secure());
    await GlyfBridge.walletSecretSave(_keyName, _hex32(key));
    _key = key;
    address.value = key.address.hexEip55;
    await _share();
    return address.value!;
  }

  /// Forgets the key on this phone. Whatever it holds stays on chain, out of
  /// reach without the key, so the screen that calls this asks first.
  static Future<void> forget() async {
    await GlyfBridge.walletSecretClear(_keyName);
    _key = null;
    address.value = null;
    await GlyfBridge.updateSharedSettings((s) => s..remove('evmAddress'));
  }

  /// The keyboard reads the address from shared settings: balances, its own
  /// address getting no Send chip, and whose requests are whose.
  static Future<void> _share() => GlyfBridge.updateSharedSettings((s) => s..['evmAddress'] = address.value);

  /// The key as exactly 32 bytes: web3dart's own bytes carry a sign byte
  /// (33 long) whenever the top bit is set.
  static String _hex32(EthPrivateKey key) => key.privateKeyInt.toRadixString(16).padLeft(64, '0');

  static Uint8List get _keyBytes => hexToBytes(_hex32(_signer));

  static EthPrivateKey get _signer {
    final key = _key;
    if (key == null) throw StateError('no wallet');
    return key;
  }

  /// Builds, signs and sends one transaction; resolves with its hash.
  /// Fees are EIP-1559 from the chain's own fee history, nonce from the
  /// pending pool, gas from an estimate with a fifth on top.
  static Future<String> send(EvmChain chain, EvmCall call) async {
    final key = _signer;
    final from = key.address.hexEip55;
    final nonce = await EvmRpc.nonce(chain, from);
    final fees = await EvmRpc.fees(chain);
    final gas = call.gas ??
        (await EvmRpc.estimateGas(chain, from: from, to: call.to, data: call.data, value: call.value)) * BigInt.from(6) ~/
            BigInt.from(5);
    final tx = Transaction(
      to: EthereumAddress.fromHex(call.to),
      value: EtherAmount.inWei(call.value),
      data: call.data == null ? null : hexToBytes(call.data!),
      nonce: nonce,
      maxGas: gas.toInt(),
      maxFeePerGas: EtherAmount.inWei(fees.maxFee),
      maxPriorityFeePerGas: EtherAmount.inWei(fees.tip),
    );
    final raw = prependTransactionType(0x02, signTransactionRaw(tx, key, chainId: chain.id));
    return EvmRpc.sendRaw(chain, '0x${bytesToHex(raw)}');
  }

  /// EIP-712 typed data (Flash orders, Permit2), as a 0x signature.
  static String signTypedData(Object typedData) => EthSigUtil.signTypedData(
        privateKeyInBytes: _keyBytes,
        jsonData: typedData is String ? typedData : jsonEncode(typedData),
        version: TypedDataVersion.V4,
      );

  /// A plain message (personal_sign).
  static String signMessage(Uint8List message) =>
      '0x${bytesToHex(_signer.signPersonalMessageToUint8List(message))}';

  /// Raw secp256k1 over a 32-byte digest, for protocols that hash their own
  /// payload (Arkiv's entity transactions).
  static Uint8List signDigest(Uint8List digest, {int? chainId}) =>
      _signer.signToUint8List(digest, chainId: chainId);

  static Uint8List keccak(Uint8List bytes) => keccak256(bytes);
}

/// One contract call or transfer to sign.
class EvmCall {
  EvmCall({required this.to, this.data, BigInt? value, this.gas}) : value = value ?? BigInt.zero;

  final String to;

  /// 0x calldata, or nil for a plain transfer.
  final String? data;
  final BigInt value;

  /// Known gas, skipping the estimate (a transfer's 21,000).
  final BigInt? gas;

  static EvmCall fromJson(Map<String, dynamic> j) => EvmCall(
        to: j['to'] as String,
        data: j['data'] as String?,
        value: BigInt.parse((j['value'] ?? '0').toString().replaceFirst('0x', ''),
            radix: (j['value'] ?? '').toString().startsWith('0x') ? 16 : 10),
        gas: j['gas'] == null ? null : BigInt.parse(j['gas'].toString()),
      );
}
