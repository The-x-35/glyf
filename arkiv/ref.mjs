// Reference run of the Glyf Vault on Arkiv (Rabdi testnet) with the official
// SDK: create one encrypted vault item, find it by owner, edit it, extend it,
// delete it, and read every step back the way a second phone would.
//
//   node keygen.mjs   once: throwaway vault secret in arkiv/.key (never printed)
//   node ref.mjs      simulate on the live node (no funds needed), then, if the
//                     owner has tGLM, run it for real and log the txs to ref-run.json
//
// ARKIV_ACCESS_KEY (optional) uses a hub.arkiv.network access key instead of
// the heavily rate-limited public endpoint.
import fs from 'node:fs';
import { formatEther, hexToBytes, http, toFunctionSelector } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { createPublicClient, createWalletClient, ExpirationTime } from '@arkiv-network/sdk';
import { rabdi } from '@arkiv-network/sdk/chains';
import { eq } from '@arkiv-network/sdk/query';
import { bytes, defineSchema, key, u64 } from '@arkiv-network/sdk/schema';
import * as V from './vault.mjs';

const keyFile = new URL('./.key', import.meta.url);
if (!fs.existsSync(keyFile)) { console.error('no arkiv/.key: run `node keygen.mjs` first'); process.exit(1); }
const keys = V.deriveKeys(hexToBytes(fs.readFileSync(keyFile, 'utf8').trim()));
const account = privateKeyToAccount(keys.ownerKey);
const chain = rabdi({ accessKey: process.env.ARKIV_ACCESS_KEY ?? '' });
const pub = createPublicClient({ chain, transport: http() });
const wallet = createWalletClient({ chain, transport: http(), account });
const Vault = defineSchema(V.SCHEMA_TAG, { v: u64().indexed(), item: key().indexed(), ct: bytes() });
const tx = (h) => `${V.ARKIV.explorer}/tx/${h}`;
const log = { owner: keys.owner, chainId: V.ARKIV.chainId, startedAt: new Date().toISOString(), steps: [] };
const step = (name, data) => { log.steps.push({ name, ...data }); console.log(`- ${name}`, data); };

const item = { id: 'field:addr-home', type: 'field', kind: 'address', label: 'Home', value: '1 Infinite Loop, Cupertino, CA 95014', updatedAt: Date.now() };
console.log(`owner ${keys.owner} on Rabdi (${V.ARKIV.chainId})`);

// ---------------------------------------------------------------- 1. simulate
// The batch create -> patch -> extend -> delete in one eth_estimateGas: the
// node runs each operation against the one before it, so this proves the
// hand-rolled encoding and the predicted entity key on the real engine,
// without spending anything.
{
  const enc = V.encryptItem(keys, item);
  const salt = V.randomSalt();
  const nonce = BigInt(await V.rpc('eth_call', [{ to: V.ARKIV.address, data: V.entityNonceCalldata(keys.owner) }, 'latest']));
  const k = V.predictEntityKey({ owner: keys.owner, nonce, salt });
  const ops = [
    V.createOp({ salt, attributes: V.vaultAttributes(enc) }),
    V.patchOp({ entityKey: k, mutations: V.vaultPatchMutations(V.encryptItem(keys, { ...item, value: 'edited' })) }),
    V.extendOp({ entityKey: k, minLifetime: V.LIFETIME_BLOCKS + 100n }),
    V.deleteOp({ entityKey: k }),
  ];
  const gas = BigInt(await V.rpc('eth_estimateGas', [{ from: keys.owner, to: V.ARKIV.address, data: V.executeCalldata(ops) }]));
  const gasCreate = BigInt(await V.rpc('eth_estimateGas', [{ from: keys.owner, to: V.ARKIV.address, data: V.executeCalldata([ops[0]]) }]));
  // and a broken one must revert with AttributesNotSorted()
  let unsorted;
  try {
    await V.rpc('eth_call', [{ from: keys.owner, to: V.ARKIV.address, data: V.executeCalldata([V.createOp({ salt, attributes: V.vaultAttributes(enc).reverse() })]) }, 'latest']);
  } catch (e) { unsorted = e.rpcError?.data; }
  if (unsorted !== toFunctionSelector('AttributesNotSorted()')) throw new Error(`expected AttributesNotSorted, got ${unsorted}`);
  step('simulated create+patch+extend+delete on the live node', { entityNonce: nonce.toString(), predictedKey: k, gasBatchOf4: gas.toString(), gasCreate: gasCreate.toString(), unsortedReverts: unsorted });
}

const balance = await pub.getBalance({ address: keys.owner });
console.log(`balance ${formatEther(balance)} tGLM`);
if (balance === 0n) {
  console.log(`\nno tGLM: fund ${keys.owner} at https://hub.arkiv.network/faucet and run again for the live writes.`);
  process.exit(2);
}

// ------------------------------------------------------------------ 2. create
const enc1 = V.encryptItem(keys, item);
const salt = V.randomSalt();
const nonce = await pub.getEntityNonce(keys.owner);
const predicted = V.predictEntityKey({ owner: keys.owner, nonce, salt });
const created = await wallet.createEntity(
  Vault,
  { v: u64(V.FORMAT_V), item: key(enc1.item), ct: bytes(enc1.ct) },
  { expiration: ExpirationTime.fromDays(V.LIFETIME_DAYS), flags: { permissionlessExtension: true }, salt },
);
if (created.entityKey !== predicted) throw new Error(`key ${created.entityKey} != predicted ${predicted}`);
step('create', { entityKey: created.entityKey, predictedKeyMatches: true, expiresAt: created.expiresAt.toString(), tx: tx(created.txHash) });

// ------------------------------------------- 3. restore on a "second phone"
// Only the vault secret is shared. Everything else is derived and queried.
{
  const second = V.deriveKeys(hexToBytes(fs.readFileSync(keyFile, 'utf8').trim()));
  // (a) through the SDK
  const page = await pub.select().from(Vault).ownedBy(second.owner).fetch();
  const viaSdk = page.entities.map((r) => V.decryptItem(second, r.item.value, r.ct.value));
  // (b) the raw JSON-RPC a Dart port sends
  const [q, opts] = V.restoreQuery(second.owner);
  const raw = await V.rpc('arkiv_query', [q, opts]);
  const viaRpc = raw.data.map(V.readVaultEntity).filter(Boolean).map((e) => V.decryptItem(second, e.item, e.ct));
  if (!viaRpc.some((x) => x.id === item.id && x.value === item.value)) throw new Error('restore did not find the item');
  step('restore by owner', { query: q, sdkRows: viaSdk.length, rpcRows: viaRpc.length, decrypted: viaRpc.find((x) => x.id === item.id) });
}

// ------------------------------------------------------------------- 4. edit
const edited = { ...item, value: '1 Apple Park Way, Cupertino, CA 95014', updatedAt: Date.now() };
const enc2 = V.encryptItem(keys, edited);
const patched = await wallet.patchEntity(Vault, created.entityKey, { set: { ct: bytes(enc2.ct), v: u64(V.FORMAT_V) } });
const afterPatch = await V.rpc('arkiv_getEntity', [created.entityKey]);
const e2 = V.readVaultEntity(afterPatch);
const d2 = V.decryptItem(keys, e2.item, e2.ct);
if (d2.value !== edited.value) throw new Error('patch not visible');
step('patch (edit item)', { tx: tx(patched.txHash), readBack: d2.value });

// one item found by its hash, the way an edit finds what to replace
{
  const page = await pub.select({ $key: true }).from(Vault).where(eq('item', key(enc1.item))).ownedBy(keys.owner).fetch();
  step('find by item hash', { matches: page.entities.map((r) => r.$key) });
}

// ----------------------------------------------------------------- 5. extend
const ext = await wallet.extendEntity({ entityKey: created.entityKey, expiration: ExpirationTime.fromDays(V.LIFETIME_DAYS + 1) });
step('extend', { tx: tx(ext.txHash), expiresAt: ext.expiresAt?.toString() });

// ----------------------------------------------------------------- 6. delete
const del = await wallet.deleteEntity({ entityKey: created.entityKey });
const gone = await V.rpc('arkiv_getEntity', [created.entityKey]);
if (gone !== null) throw new Error('entity still there after delete');
step('delete', { tx: tx(del.txHash), getEntityAfter: gone });

// ------------------------------------------- 7. one item that stays (judges)
// A shorthand left alive for 90 days so the query in schema.md returns
// something. Created once: a rerun finds it by its item hash and skips.
{
  const kept = { id: 'snippet:;mail', type: 'snippet', trigger: ';mail', text: 'hello@tryglyf.com', updatedAt: Date.now() };
  const h = V.itemHash(keys, kept.id);
  const existing = await pub.select({ $key: true }).from(Vault).where(eq('item', key(h))).ownedBy(keys.owner).fetch();
  if (existing.entities.length) {
    step('kept item already there', { entityKey: existing.entities[0].$key });
  } else {
    const enc = V.encryptItem(keys, kept);
    const c = await wallet.createEntity(Vault, { v: u64(V.FORMAT_V), item: key(enc.item), ct: bytes(enc.ct) },
      { expiration: ExpirationTime.fromDays(V.LIFETIME_DAYS), flags: { permissionlessExtension: true } });
    step('kept item created', { entityKey: c.entityKey, expiresAt: c.expiresAt.toString(), tx: tx(c.txHash) });
  }
}

log.finishedAt = new Date().toISOString();
fs.writeFileSync(new URL('./ref-run.json', import.meta.url), JSON.stringify(log, null, 2) + '\n');
console.log('\nall steps passed; transactions logged in arkiv/ref-run.json');
