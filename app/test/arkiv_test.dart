import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/arkiv_vault.dart';
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;
import 'package:web3dart/web3dart.dart';

/// The Dart port of arkiv/vault.mjs against arkiv/vectors.json, whose writes
/// the official Arkiv SDK built byte for byte.
void main() {
  final v = jsonDecode(File('../arkiv/vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final inputs = v['inputs'] as Map<String, dynamic>;
  final writes = v['writes'] as Map<String, dynamic>;
  final keys = VaultKeys.derive(hexToBytes(inputs['vaultSecret'] as String));
  final item = Map<String, Object?>.from(inputs['item'] as Map);
  final edited = Map<String, Object?>.from(inputs['itemEdited'] as Map);
  String hex(List<int> b) => '0x${bytesToHex(b)}';

  test('the secret derives the same owner, AES and item keys', () {
    final k = v['keys'] as Map<String, dynamic>;
    expect(keys.ownerKey, k['ownerPrivateKey']);
    expect(keys.owner, k['ownerAddress']);
    expect(hex(keys.aesKey), k['aesKey']);
    expect(hex(keys.itemKey), k['itemKey']);
  });

  test('an item hashes, pads, binds and seals the same way', () {
    final x = v['item'] as Map<String, dynamic>;
    final h = keys.itemHash(item['id'] as String);
    expect(h, x['itemHash']);
    expect(jsonEncode(item), x['json']);
    expect(hex(VaultKeys.pad(jsonEncode(item))), x['paddedPlaintext']);
    expect(hex(keys.aad(h)), x['aad']);
    final ct = keys.encrypt(item, nonce: hexToBytes(inputs['aesNonce1'] as String));
    expect(hex(ct), x['ct']);
    expect(keys.decrypt(h, ct)['value'], item['value']);
    expect(hex(keys.encrypt(edited, nonce: hexToBytes(inputs['aesNonce2'] as String))), x['ctEdited']);
  });

  Transaction tx(int nonce, List<int> data) {
    final t = inputs['tx'] as Map<String, dynamic>;
    return Transaction(
      to: EthereumAddress.fromHex(t['to'] as String),
      value: EtherAmount.zero(),
      data: hexToBytes(hex(data)),
      nonce: nonce,
      maxGas: int.parse(t['gas'] as String),
      maxFeePerGas: EtherAmount.inWei(BigInt.parse(t['maxFeePerGas'] as String)),
      maxPriorityFeePerGas: EtherAmount.inWei(BigInt.parse(t['maxPriorityFeePerGas'] as String)),
    );
  }

  void sameWrite(String name, Uint8List op, int nonce) {
    final w = writes[name] as Map<String, dynamic>;
    final ops = (w['operations'] as List).cast<Map>();
    expect(ops.single['operation'], op[31], reason: '$name operation');
    final calldata = ArkivVault.executeCalldata([op]);
    expect(hex(calldata), w['calldata'], reason: '$name calldata');
    final key = EthPrivateKey.fromHex(keys.ownerKey);
    expect(ArkivVault.signedTx(key, tx(nonce, calldata)), w['rawSignedTx'], reason: '$name signed tx');
  }

  test('create, patch, extend and delete are the SDK’s bytes', () {
    final h = keys.itemHash(item['id'] as String);
    final salt = BigInt.parse((inputs['salt'] as String).substring(2), radix: 16);
    final nonces = (inputs['tx'] as Map)['nonces'] as Map;
    final ct = keys.encrypt(item, nonce: hexToBytes(inputs['aesNonce1'] as String));
    sameWrite('create', ArkivVault.createOp(salt, ArkivVault.vaultAttributes(h, ct)), nonces['create'] as int);

    final entity = ArkivVault.predictKey(keys.owner, BigInt.parse(inputs['entityNonceBeforeCreate'] as String), salt);
    expect(entity, writes['predictedEntityKey']);
    final ct2 = keys.encrypt(edited, nonce: hexToBytes(inputs['aesNonce2'] as String));
    sameWrite('patch', ArkivVault.patchOp(entity, [Attr.bytes('ct', ct2), Attr.u64('v', BigInt.one)]),
        nonces['patch'] as int);
    sameWrite('extend', ArkivVault.extendOp(entity), nonces['extend'] as int);
    sameWrite('delete', ArkivVault.deleteOp(entity), nonces['delete'] as int);
  });

  test('the restore query is the one judges can run', () {
    final q = ArkivVault.restoreQuery(keys.owner, null);
    final want = (v['reads'] as Map)['restoreFirstPage'];
    final params = want is Map ? want['params'] : want;
    expect(jsonEncode(q), jsonEncode(params));
  });

  test('a query row reads back into the item', () {
    final reads = v['reads'] as Map<String, dynamic>;
    final e = VaultEntity.read(Map<String, dynamic>.from(reads['sampleResultEntity'] as Map));
    expect(e, isNotNull);
    final got = keys.decrypt(e!.item, e.ct);
    final want = reads['sampleDecrypted'] as Map;
    expect(got['value'], want['value']);
  });
}
