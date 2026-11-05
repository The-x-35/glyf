import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as sha;
import 'package:pointycastle/export.dart' show AEADParameters, GCMBlockCipher, AESEngine, KeyParameter;
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes, keccak256;
import 'package:web3dart/web3dart.dart';

import '../core/bridge.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';

/// The Vault backed up on Arkiv (arkiv/DESIGN.md, arkiv/PROTOCOL.md): one
/// encrypted entity per saved detail, shorthand or combo, owned by a key
/// derived from a secret that iCloud Keychain carries to the person's next
/// phone. Arkiv sees an owner, an opaque item hash and ciphertext; the
/// details never leave the phone readable. A port of arkiv/vault.mjs,
/// checked against arkiv/vectors.json byte for byte (test/arkiv_test.dart).
abstract final class ArkivVault {
  static EvmChain get chain => EvmChain.arkiv;
  static const address = '0x4400000000000000000000000000000000000044';
  static const schemaTag = 'glyf-vault';

  /// 90 days at Arkiv's 2-second blocks, renewed when under 30 are left.
  static final lifetimeBlocks = BigInt.from(90 * 86400 ~/ 2);
  static final renewBelowBlocks = BigInt.from(30 * 86400 ~/ 2);

  /// permissionlessExtension: anyone may extend, only the owner may change.
  static const creationFlags = 2;
  static const _secretName = 'arkiv-vault-secret-v1';

  // MARK: keys

  /// The 32-byte vault secret, made once and kept in iCloud Keychain.
  static Future<Uint8List> secret() async {
    final saved = await GlyfBridge.walletSecretLoad(_secretName);
    if (saved != null && saved.length == 64) return hexToBytes(saved);
    final r = Random.secure();
    final fresh = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    await GlyfBridge.walletSecretSave(_secretName, bytesToHex(fresh), sync: true);
    return fresh;
  }

  static Future<VaultKeys> keys() async => VaultKeys.derive(await secret());

  // MARK: items

  /// The Vault's items as backup items: fields, shorthand, combos (pictures
  /// stay on the phone). Ids follow DESIGN.md.
  static List<Map<String, Object?>> itemsOf(Map<String, dynamic> vault) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final f in (vault['fields'] as List? ?? const []).cast<Map>())
        {
          'id': 'field:${f['id']}', 'type': 'field', 'kind': f['kind'], 'label': f['label'], 'value': f['value'],
          'updatedAt': f['updatedAt'] ?? now,
        },
      for (final s in (vault['snippets'] as List? ?? const []).cast<Map>())
        {'id': 'snippet:${s['trigger']}', 'type': 'snippet', 'trigger': s['trigger'], 'text': s['text'], 'updatedAt': s['updatedAt'] ?? now},
      for (final c in (vault['combos'] as List? ?? const []).cast<Map>())
        {'id': 'combo:${c['id']}', 'type': 'combo', 'label': c['label'], 'fieldIds': c['fieldIds'], 'updatedAt': c['updatedAt'] ?? now},
    ];
  }

  // MARK: backing up

  /// Writes every item that isn't on Arkiv yet (or changed), deletes what
  /// was removed from the Vault, and extends what's close to expiring, in one
  /// transaction. Resolves with the transaction hash, or null when nothing
  /// needed writing.
  static Future<({String? txHash, int written, int removed, int kept})> backUp(Map<String, dynamic> vault) async {
    final k = await keys();
    final onChain = await restoreEntities(k);
    final byItem = {for (final e in onChain) e.item: e};
    final ops = <Uint8List>[];
    final wanted = <String>{};
    var written = 0;
    for (final item in itemsOf(vault)) {
      final h = k.itemHash(item['id'] as String);
      wanted.add(h);
      final existing = byItem[h];
      if (existing != null) {
        // The same content needs no write; a changed one is a patch.
        final old = _tryDecrypt(k, existing);
        if (old != null && jsonEncode(_comparable(old)) == jsonEncode(_comparable(item))) continue;
        ops.add(patchOp(existing.key, [
          Attr.bytes('ct', k.encrypt(item)),
          Attr.u64('v', BigInt.one),
        ]));
      } else {
        final salt = _salt();
        ops.add(createOp(salt, vaultAttributes(h, k.encrypt(item))));
      }
      written++;
    }
    var removed = 0;
    for (final e in onChain) {
      if (!wanted.contains(e.item)) {
        ops.add(deleteOp(e.key));
        removed++;
      }
    }
    final block = await currentBlock();
    for (final e in onChain) {
      if (wanted.contains(e.item) && e.expiresAt != null && e.expiresAt! < block + renewBelowBlocks) {
        ops.add(extendOp(e.key));
      }
    }
    if (ops.isEmpty) return (txHash: null, written: 0, removed: 0, kept: onChain.length);
    final hash = await _send(k, executeCalldata(ops));
    final r = await EvmRpc.receipt(chain, hash);
    if (r == null || !EvmRpc.succeeded(r)) throw EvmRpcException('Arkiv didn’t take the backup');
    return (txHash: hash, written: written, removed: removed, kept: onChain.length - removed);
  }

  /// Everything backed up, decrypted: what a new phone puts back in its Vault.
  static Future<List<Map<String, dynamic>>> restore() async {
    final k = await keys();
    final items = <String, Map<String, dynamic>>{};
    for (final e in await restoreEntities(k)) {
      final item = _tryDecrypt(k, e);
      if (item == null) continue;
      final id = item['id'] as String;
      final had = items[id];
      if (had == null || (item['updatedAt'] as num? ?? 0) > (had['updatedAt'] as num? ?? 0)) items[id] = item;
    }
    return items.values.toList();
  }

  static Map<String, dynamic>? _tryDecrypt(VaultKeys k, VaultEntity e) {
    try {
      return k.decrypt(e.item, e.ct);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _comparable(Map item) => {...item}..remove('updatedAt');

  static BigInt _salt() {
    final r = Random.secure();
    return BigInt.parse(List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join(), radix: 16);
  }

  // MARK: reads

  /// Every vault entity this owner has, a page of 100 at a time.
  static Future<List<VaultEntity>> restoreEntities(VaultKeys k) async {
    final out = <VaultEntity>[];
    String? after;
    while (true) {
      final res = await EvmRpc.call(chain, 'arkiv_query', restoreQuery(k.owner, after));
      final rows = ((res is Map ? (res['data'] ?? res['entities']) : res) as List? ?? const []).cast<Map>();
      for (final row in rows) {
        final e = VaultEntity.read(Map<String, dynamic>.from(row));
        if (e != null) out.add(e);
      }
      if (rows.length < 100) break;
      after = rows.last['key'] as String;
    }
    return out;
  }

  static List<Object> restoreQuery(String owner, String? afterKey) {
    final parts = ["arkiv.schema = str('$schemaTag')", '\$owner = addr($owner)', if (afterKey != null) '\$key > key($afterKey)'];
    return [
      '${parts.join(' AND ')} ORDER BY \$key ASC',
      {
        'select': {'key': true, 'owner': true, 'expiresAt': true, 'updatedAt': true, 'attributes': true},
        'limit': '0x64',
      },
    ];
  }

  static Future<BigInt> entityNonce(String owner) async {
    final raw = await EvmRpc.call(chain, 'eth_call', [
      {'to': address, 'data': entityNonceCalldata(owner)},
      'latest',
    ]) as String;
    return raw.length <= 2 ? BigInt.zero : BigInt.parse(raw.substring(2), radix: 16);
  }

  static String entityNonceCalldata(String owner) =>
      '0x36917bfd${owner.substring(2).toLowerCase().padLeft(64, '0')}';

  static Future<BigInt> currentBlock() async {
    final t = await EvmRpc.call(chain, 'arkiv_getBlockTiming', const []);
    final n = t is Map ? t['current_block'] : null;
    return BigInt.from((n as num?) ?? 0);
  }

  // MARK: the wire format (PROTOCOL.md)

  static Uint8List createOp(BigInt salt, List<Attr> attributes, {BigInt? expiresAt, BigInt? minLifetime}) =>
      _op(1, _encodeTuple([
        _Word.uint(salt),
        _Word.uint(expiresAt ?? BigInt.zero),
        _Word.uint(minLifetime ?? lifetimeBlocks),
        _Word.uint(BigInt.from(creationFlags)),
        _Dyn(_attrArray(attributes)),
      ]));

  static Uint8List patchOp(String entityKey, List<Attr> mutations) =>
      _op(2, _encodeTuple([_Word.bytes32(entityKey), _Dyn(_attrArray(mutations))]));

  static Uint8List extendOp(String entityKey, {BigInt? expiresAt, BigInt? minLifetime}) => _op(
      3,
      _encodeStatic([
        _Word.bytes32(entityKey),
        _Word.uint(expiresAt ?? BigInt.zero),
        _Word.uint(minLifetime ?? lifetimeBlocks),
      ]));

  static Uint8List deleteOp(String entityKey) => _op(5, _encodeStatic([_Word.bytes32(entityKey)]));

  /// The four attributes of a vault entity, sorted by name as the node wants.
  static List<Attr> vaultAttributes(String itemHash, Uint8List ct) => [
        Attr.str('arkiv.schema', schemaTag),
        Attr.bytes('ct', ct),
        Attr.key('item', itemHash),
        Attr.u64('v', BigInt.one),
      ];

  /// execute((uint8 operation, bytes operationData)[] ops).
  static Uint8List executeCalldata(List<Uint8List> ops) {
    final elems = [for (final op in ops) op];
    return Uint8List.fromList([...hexToBytes('49650044'), ..._word(BigInt.from(32)), ..._dynArray(elems)]);
  }

  /// keccak256(chainId uint256 ‖ 0x44…44 ‖ owner ‖ nonce uint64 ‖ salt uint128), packed.
  static String predictKey(String owner, BigInt nonce, BigInt salt) => '0x${bytesToHex(keccak256(Uint8List.fromList([
        ..._word(BigInt.from(chain.id)),
        ...hexToBytes(address),
        ...hexToBytes(owner),
        ..._fixed(nonce, 8),
        ..._fixed(salt, 16),
      ])))}';

  // ABI pieces. Each operation is (uint8 operation, bytes operationData),
  // itself a dynamic tuple inside the ops array.
  static Uint8List _op(int operation, Uint8List data) =>
      Uint8List.fromList([..._word(BigInt.from(operation)), ..._word(BigInt.from(64)), ..._bytes(data)]);

  static Uint8List _attrArray(List<Attr> attrs) {
    final sorted = [...attrs]..sort((a, b) => _compare(a.name, b.name));
    return _dynArray([
      for (final a in sorted)
        Uint8List.fromList([..._name32(a.name), ..._word(BigInt.from(a.typeId)), ..._word(BigInt.from(96)), ..._bytes(a.value)]),
    ]);
  }

  static int _compare(String a, String b) {
    final x = _name32(a), y = _name32(b);
    for (var i = 0; i < 32; i++) {
      if (x[i] != y[i]) return x[i] - y[i];
    }
    return 0;
  }

  /// An array of dynamic elements: length, each element's offset, then them.
  static Uint8List _dynArray(List<Uint8List> elems) {
    final out = BytesBuilder()..add(_word(BigInt.from(elems.length)));
    var offset = 32 * elems.length;
    for (final e in elems) {
      out.add(_word(BigInt.from(offset)));
      offset += e.length;
    }
    for (final e in elems) {
      out.add(e);
    }
    return out.toBytes();
  }

  /// abi.encode of one dynamic tuple: its offset, its head, its tails.
  static Uint8List _encodeTuple(List<Object> fields) {
    final head = BytesBuilder();
    final tail = BytesBuilder();
    final headSize = 32 * fields.length;
    for (final f in fields) {
      if (f is _Dyn) {
        head.add(_word(BigInt.from(headSize + tail.length)));
        tail.add(f.bytes);
      } else {
        head.add((f as _Word).bytes);
      }
    }
    return Uint8List.fromList([..._word(BigInt.from(32)), ...head.toBytes(), ...tail.toBytes()]);
  }

  /// abi.encode of one static tuple: just its words.
  static Uint8List _encodeStatic(List<_Word> fields) => Uint8List.fromList([for (final f in fields) ...f.bytes]);

  static Uint8List _bytes(Uint8List b) {
    final padded = (b.length + 31) ~/ 32 * 32;
    return Uint8List.fromList([..._word(BigInt.from(b.length)), ...b, ...List.filled(padded - b.length, 0)]);
  }

  static Uint8List _word(BigInt v) => _fixed(v, 32);

  static Uint8List _fixed(BigInt v, int size) {
    final hex = v.toRadixString(16).padLeft(size * 2, '0');
    return hexToBytes(hex.substring(hex.length - size * 2));
  }

  static Uint8List _name32(String name) {
    final b = utf8.encode(name);
    return Uint8List.fromList([...b, ...List.filled(32 - b.length, 0)]);
  }

  // MARK: signing

  static Future<String> _send(VaultKeys k, Uint8List calldata) async {
    final key = EthPrivateKey.fromHex(k.ownerKey);
    final nonce = await EvmRpc.nonce(chain, k.owner);
    final fees = await EvmRpc.fees(chain);
    final gas = await EvmRpc.estimateGas(chain, from: k.owner, to: address, data: '0x${bytesToHex(calldata)}');
    final capped = gas * BigInt.from(5) ~/ BigInt.from(4);
    final tx = Transaction(
      to: EthereumAddress.fromHex(address),
      value: EtherAmount.zero(),
      data: calldata,
      nonce: nonce,
      maxGas: capped > BigInt.from(16777216) ? 16777216 : capped.toInt(),
      maxFeePerGas: EtherAmount.inWei(fees.maxFee < BigInt.from(1000000000) ? BigInt.from(1000000000) : fees.maxFee),
      maxPriorityFeePerGas: EtherAmount.inWei(fees.tip),
    );
    return EvmRpc.sendRaw(chain, signedTx(key, tx));
  }

  static String signedTx(EthPrivateKey key, Transaction tx) =>
      '0x${bytesToHex(prependTransactionType(0x02, signTransactionRaw(tx, key, chainId: chain.id)))}';
}

/// The owner key, the AES-256-GCM key and the item-hash key, all from the
/// one vault secret (HKDF-SHA256).
class VaultKeys {
  VaultKeys._(this.ownerKey, this.owner, this.aesKey, this.itemKey);

  final String ownerKey;
  final String owner;
  final Uint8List aesKey;
  final Uint8List itemKey;

  static final _n = BigInt.parse('fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141', radix: 16);
  static final _salt = utf8.encode('glyf-vault-hkdf-v1');

  static VaultKeys derive(Uint8List secret) {
    String? owner;
    for (var i = 0; i < 256 && owner == null; i++) {
      final k = hkdf(secret, Uint8List.fromList([...utf8.encode('glyf/vault/v1/arkiv-owner'), i]));
      final n = BigInt.parse(bytesToHex(k), radix: 16);
      if (n != BigInt.zero && n < _n) owner = bytesToHex(k).padLeft(64, '0');
    }
    final key = EthPrivateKey.fromHex(owner!);
    return VaultKeys._('0x$owner', key.address.hexEip55, hkdf(secret, utf8.encode('glyf/vault/v1/aes-256-gcm')),
        hkdf(secret, utf8.encode('glyf/vault/v1/item-id')));
  }

  /// HKDF-SHA256, 32 bytes out.
  static Uint8List hkdf(Uint8List secret, List<int> info) {
    final prk = sha.Hmac(sha.sha256, _salt).convert(secret).bytes;
    final t = sha.Hmac(sha.sha256, prk).convert([...info, 1]).bytes;
    return Uint8List.fromList(t);
  }

  /// The indexed "item" attribute: HMAC-SHA256(itemKey, item id).
  String itemHash(String itemId) => '0x${bytesToHex(sha.Hmac(sha.sha256, itemKey).convert(utf8.encode(itemId)).bytes)}';

  /// "glyf-vault/v1" ‖ chainId uint64 ‖ owner ‖ item hash.
  Uint8List aad(String itemHash, {int chainId = 7794095}) => Uint8List.fromList([
        ...utf8.encode('glyf-vault/v1'),
        ...ArkivVault._fixed(BigInt.from(chainId), 8),
        ...hexToBytes(owner),
        ...hexToBytes(itemHash),
      ]);

  static Uint8List pad(String json) {
    final b = utf8.encode(json);
    final size = max(128, (b.length + 127) ~/ 128 * 128);
    return Uint8List.fromList([...b, ...List.filled(size - b.length, 0)]);
  }

  /// "ct" = 0x01 ‖ nonce (12) ‖ ciphertext ‖ tag (16).
  Uint8List encrypt(Map<String, Object?> item, {Uint8List? nonce}) {
    final iv = nonce ?? Uint8List.fromList(List.generate(12, (_) => Random.secure().nextInt(256)));
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, aad(itemHash(item['id'] as String))));
    final sealed = gcm.process(pad(jsonEncode(item)));
    return Uint8List.fromList([1, ...iv, ...sealed]);
  }

  Map<String, dynamic> decrypt(String itemHashHex, Uint8List ct) {
    if (ct.isEmpty || ct[0] != 1 || ct.length < 29) throw const FormatException('unknown ct format');
    final iv = ct.sublist(1, 13);
    final gcm = GCMBlockCipher(AESEngine())..init(false, AEADParameters(KeyParameter(aesKey), 128, iv, aad(itemHashHex)));
    final plain = gcm.process(ct.sublist(13));
    var n = plain.length;
    while (n > 0 && plain[n - 1] == 0) {
      n--;
    }
    final obj = jsonDecode(utf8.decode(plain.sublist(0, n))) as Map<String, dynamic>;
    if (itemHash(obj['id'] as String) != itemHashHex.toLowerCase()) throw const FormatException('item id mismatch');
    return obj;
  }
}

/// One attribute: a name, Arkiv's type id (0x80 = indexed) and the value.
class Attr {
  const Attr(this.name, this.typeId, this.value);
  final String name;
  final int typeId;
  final Uint8List value;

  factory Attr.str(String name, String v) => Attr(name, 0x88, Uint8List.fromList(utf8.encode(v)));
  factory Attr.bytes(String name, Uint8List v) => Attr(name, 0x07, v);
  factory Attr.key(String name, String hex32) => Attr(name, 0x8a, hexToBytes(hex32));
  factory Attr.u64(String name, BigInt v) => Attr(name, 0x83, ArkivVault._word(v));
}

/// A vault entity read back from arkiv_query.
class VaultEntity {
  const VaultEntity(this.key, this.item, this.ct, this.expiresAt);
  final String key;
  final String item;
  final Uint8List ct;
  final BigInt? expiresAt;

  static VaultEntity? read(Map<String, dynamic> row) {
    final attrs = {
      for (final a in (row['attributes'] as List? ?? const []).cast<Map>()) a['name'] as String: a,
    };
    if (attrs['arkiv.schema']?['value'] != ArkivVault.schemaTag) return null;
    final item = attrs['item'], ct = attrs['ct'];
    if (item == null || ct == null || item['type'] != 'key' || ct['type'] != 'bytes') return null;
    final exp = row['expiresAt'];
    return VaultEntity(
      row['key'] as String,
      (item['value'] as String).toLowerCase(),
      hexToBytes(ct['value'] as String),
      exp == null ? null : BigInt.parse('$exp'.replaceFirst('0x', ''), radix: '$exp'.startsWith('0x') ? 16 : 10),
    );
  }
}

class _Word {
  const _Word(this.bytes);
  final Uint8List bytes;
  factory _Word.uint(BigInt v) => _Word(ArkivVault._word(v));
  factory _Word.bytes32(String hex) => _Word(hexToBytes(hex));
}

class _Dyn {
  const _Dyn(this.bytes);
  final Uint8List bytes;
}
