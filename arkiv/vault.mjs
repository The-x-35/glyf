// Glyf Vault on Arkiv: the whole client-side format in one file, with no
// Arkiv SDK. This is the reference a Dart (app) or Swift (keyboard) port
// copies line for line; vectors.mjs checks it byte for byte against what the
// official SDK (@arkiv-network/sdk) builds for the same inputs.
//
// Spec: DESIGN.md (keys, encryption, attributes) and PROTOCOL.md (wire format).
import crypto from 'node:crypto';
import {
  bytesToHex, concatHex, encodeAbiParameters, encodeFunctionData, encodePacked, hexToBytes,
  keccak256, numberToHex, parseAbi, parseAbiParameters, toHex,
} from 'viem';
import { privateKeyToAddress } from 'viem/accounts';

// ------------------------------------------------------------ chain (Rabdi)

export const ARKIV = {
  chainId: 7794095,
  rpc: 'https://rpc.rabdi.db-chain.testnet.arkiv.network',
  explorer: 'https://rabdi.explorer.arkiv.network',
  address: '0x4400000000000000000000000000000000000044', // every write is execute() on this
  blockTime: 2, // seconds
  maxLifetime: 7_884_000n, // blocks, about 182.5 days
};

// ---------------------------------------------------------- vault constants

export const SCHEMA_TAG = 'glyf-vault'; // value of the indexed str attribute "arkiv.schema"
export const FORMAT_V = 1n; // u64 attribute "v"
export const LIFETIME_DAYS = 90;
export const LIFETIME_BLOCKS = BigInt((LIFETIME_DAYS * 86400) / ARKIV.blockTime); // 3,888,000
export const RENEW_BELOW_BLOCKS = BigInt((30 * 86400) / ARKIV.blockTime); // renew when < 30 days left
export const CREATION_FLAGS = 0b10; // permissionlessExtension: anyone may extend, only the owner may change
export const PAD_TO = 128; // plaintext is zero-padded to a multiple of this

const HKDF_SALT = new TextEncoder().encode('glyf-vault-hkdf-v1');
const INFO_OWNER = 'glyf/vault/v1/arkiv-owner';
const INFO_AEAD = 'glyf/vault/v1/aes-256-gcm';
const INFO_ITEM = 'glyf/vault/v1/item-id';
const AAD_PREFIX = 'glyf-vault/v1';
const CT_VERSION = 0x01;
const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

const utf8 = (s) => new TextEncoder().encode(s);
const hkdf = (secret, info, len = 32) => new Uint8Array(crypto.hkdfSync('sha256', secret, HKDF_SALT, info, len));

// ------------------------------------------------------------------ keys

/// 32-byte vault secret -> owner key (secp256k1), AES-256-GCM key, item-id HMAC key.
export function deriveKeys(secret) {
  if (!(secret instanceof Uint8Array) || secret.length !== 32) throw new Error('vault secret must be 32 bytes');
  let ownerKey;
  for (let i = 0; i < 256; i++) {
    const k = hkdf(secret, new Uint8Array([...utf8(INFO_OWNER), i]));
    const n = BigInt(bytesToHex(k));
    if (n !== 0n && n < SECP256K1_N) { ownerKey = bytesToHex(k); break; }
  }
  return {
    ownerKey, // 0x + 64 hex: the Arkiv account that owns every vault entity
    owner: privateKeyToAddress(ownerKey),
    aesKey: hkdf(secret, utf8(INFO_AEAD)),
    itemKey: hkdf(secret, utf8(INFO_ITEM)),
  };
}

/// The indexed "item" attribute: HMAC-SHA256(itemKey, UTF-8 item id), 32 bytes.
/// Lets one item be found and replaced without saying what it is.
export function itemHash(keys, itemId) {
  return bytesToHex(new Uint8Array(crypto.createHmac('sha256', keys.itemKey).update(utf8(itemId)).digest()));
}

// ------------------------------------------------------------ encryption

/// AAD = "glyf-vault/v1" || chainId (uint64 BE) || owner (20 bytes) || item hash (32 bytes).
/// Binds a ciphertext to its chain, owner and item, so it can't be moved to another one.
export function aad(chainId, owner, item) {
  const c = new Uint8Array(8);
  new DataView(c.buffer).setBigUint64(0, BigInt(chainId));
  return new Uint8Array([...utf8(AAD_PREFIX), ...c, ...hexToBytes(owner), ...hexToBytes(item)]);
}

/// Plaintext = UTF-8 JSON of the item, zero-padded to a multiple of 128 bytes
/// (JSON never contains a 0x00 byte, so trailing zeros strip cleanly).
export function pad(json) {
  const b = utf8(json);
  const out = new Uint8Array(Math.max(PAD_TO, Math.ceil(b.length / PAD_TO) * PAD_TO));
  out.set(b);
  return out;
}
export function unpad(b) {
  let n = b.length;
  while (n > 0 && b[n - 1] === 0) n--;
  return new TextDecoder('utf-8', { fatal: true }).decode(b.subarray(0, n));
}

/// "ct" attribute = 0x01 || nonce (12) || AES-256-GCM ciphertext || tag (16).
export function encryptItem(keys, item, { chainId = ARKIV.chainId, nonce } = {}) {
  const id = item.id;
  const h = itemHash(keys, id);
  const iv = nonce ?? crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', keys.aesKey, iv);
  c.setAAD(aad(chainId, keys.owner, h));
  const body = Buffer.concat([c.update(pad(JSON.stringify(item))), c.final()]);
  const ct = new Uint8Array([CT_VERSION, ...iv, ...body, ...c.getAuthTag()]);
  return { item: h, ct: bytesToHex(ct) };
}

export function decryptItem(keys, itemHex, ctHex, { chainId = ARKIV.chainId } = {}) {
  const ct = hexToBytes(ctHex);
  if (ct[0] !== CT_VERSION || ct.length < 1 + 12 + 16) throw new Error('unknown ct format');
  const iv = ct.subarray(1, 13);
  const tag = ct.subarray(ct.length - 16);
  const d = crypto.createDecipheriv('aes-256-gcm', keys.aesKey, iv);
  d.setAAD(aad(chainId, keys.owner, itemHex));
  d.setAuthTag(tag);
  const pt = Buffer.concat([d.update(ct.subarray(13, ct.length - 16)), d.final()]);
  const obj = JSON.parse(unpad(new Uint8Array(pt)));
  if (itemHash(keys, obj.id) !== itemHex.toLowerCase()) throw new Error('item id does not match its hash');
  return obj;
}

// ------------------------------------------------- Arkiv wire format (writes)

export const EXECUTE_ABI = parseAbi(['function execute((uint8 operation, bytes operationData)[] ops) returns (bytes32[] keys)']);
const ATTR = '(bytes32 name, uint8 typeId, bytes value)[]';
const P = {
  1: parseAbiParameters(`(uint128 salt, uint64 expiresAt, uint64 minLifetime, uint8 creationFlags, ${ATTR} attributes)`),
  2: parseAbiParameters(`(bytes32 entityKey, ${ATTR} mutations)`),
  3: parseAbiParameters('(bytes32 entityKey, uint64 expiresAt, uint64 minLifetime)'),
  4: parseAbiParameters('(bytes32 entityKey, address newOwner)'),
  5: parseAbiParameters('(bytes32 entityKey)'),
};
export const OP = { create: 1, patch: 2, extend: 3, transfer: 4, delete: 5 };
export const TYPE = { tombstone: 0, bool: 1, i32: 2, u64: 3, u256: 4, dec: 5, bytes: 7, str: 8, addr: 9, key: 10 };
export const INDEXED = 0x80;

const attr = (name, typeId, value) => ({ name: toHex(name, { size: 32 }), typeId, value });
const word = (n) => toHex(n, { size: 32 });
const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

/// The four attributes of a vault entity, sorted by name as the node requires.
export function vaultAttributes({ item, ct }) {
  return [
    attr('arkiv.schema', TYPE.str | INDEXED, toHex(utf8(SCHEMA_TAG))), // 0x88
    attr('ct', TYPE.bytes, ct), //                                      0x07, never indexed
    attr('item', TYPE.key | INDEXED, item), //                          0x8a
    attr('v', TYPE.u64 | INDEXED, word(FORMAT_V)), //                   0x83
  ].sort(byName);
}

export const createOp = ({ salt, expiresAt = 0n, minLifetime = LIFETIME_BLOCKS, creationFlags = CREATION_FLAGS, attributes }) => ({
  operation: OP.create,
  operationData: encodeAbiParameters(P[1], [{ salt, expiresAt, minLifetime, creationFlags, attributes }]),
});
/// A patch only names what changes: a new ct (and v, kept equal) for an edited item.
export const patchOp = ({ entityKey, mutations }) => ({
  operation: OP.patch, operationData: encodeAbiParameters(P[2], [{ entityKey, mutations: [...mutations].sort(byName) }]),
});
export const vaultPatchMutations = ({ ct }) => [attr('ct', TYPE.bytes, ct), attr('v', TYPE.u64 | INDEXED, word(FORMAT_V))];
export const extendOp = ({ entityKey, expiresAt = 0n, minLifetime = LIFETIME_BLOCKS }) => ({
  operation: OP.extend, operationData: encodeAbiParameters(P[3], [{ entityKey, expiresAt, minLifetime }]),
});
export const deleteOp = ({ entityKey }) => ({ operation: OP.delete, operationData: encodeAbiParameters(P[5], [{ entityKey }]) });

export const executeCalldata = (ops) => encodeFunctionData({ abi: EXECUTE_ABI, functionName: 'execute', args: [ops] });

/// keccak256(chainId uint256 || arkiv address || owner || entityNonce uint64 || salt uint128), packed.
export const predictEntityKey = ({ owner, nonce, salt, chainId = ARKIV.chainId }) =>
  keccak256(encodePacked(['uint256', 'address', 'address', 'uint64', 'uint128'], [BigInt(chainId), ARKIV.address, owner, nonce, salt]));

/// eth_call data for entityNonce(address) on the Arkiv address.
export const entityNonceCalldata = (owner) => concatHex(['0x36917bfd', toHex(hexToBytes(owner), { size: 32 })]);

export const randomSalt = () => BigInt(bytesToHex(crypto.randomBytes(16)));

// --------------------------------------------------- Arkiv reads (JSON-RPC)

/// arkiv_query params that list every vault entity of one owner, one page of up to 100, paged by key.
export function restoreQuery(owner, afterKey) {
  const parts = [`arkiv.schema = str('${SCHEMA_TAG}')`, `$owner = addr(${owner})`];
  if (afterKey) parts.push(`$key > key(${afterKey})`);
  return [
    `${parts.join(' AND ')} ORDER BY $key ASC`,
    { select: { key: true, owner: true, expiresAt: true, updatedAt: true, attributes: true }, limit: numberToHex(100) },
  ];
}

/// Pulls (item, ct, v) out of one arkiv_query / arkiv_getEntity result entity.
export function readVaultEntity(rpcEntity) {
  const a = Object.fromEntries((rpcEntity.attributes ?? []).map((x) => [x.name, x]));
  if (a['arkiv.schema']?.value !== SCHEMA_TAG) return undefined;
  if (a.item?.type !== 'key' || a.ct?.type !== 'bytes') return undefined;
  return {
    key: rpcEntity.key, owner: rpcEntity.owner, expiresAt: rpcEntity.expiresAt && BigInt(rpcEntity.expiresAt),
    updatedAt: rpcEntity.updatedAt && BigInt(rpcEntity.updatedAt),
    item: a.item.value.toLowerCase(), ct: a.ct.value, v: a.v ? BigInt(a.v.value) : undefined,
  };
}

export async function rpc(method, params, url = process.env.ARKIV_RPC || ARKIV.rpc) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
    if (r.status === 429) { await new Promise((s) => setTimeout(s, 1000 * 2 ** attempt)); continue; }
    const j = await r.json();
    if (j.error) throw Object.assign(new Error(`${method}: ${j.error.message}`), { rpcError: j.error });
    return j.result;
  }
  throw new Error(`${method}: rate limited`);
}
