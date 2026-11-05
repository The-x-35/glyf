// Optional: runs GlyfPayRequest against the REAL test USDT (TetherTokenV2
// behind an EIP-1967 proxy) on a local fork of Whitechain Sepolia. Nothing is
// sent to the network: the fork is in-process, and the USDT "holder" is
// impersonated on the fork only.
//   npm run test:fork
import assert from 'node:assert/strict';
import { parseEventLogs, parseSignature, parseAbi } from 'viem';
import { chain, deploy, send, read } from './helpers.mjs';

const RPC = process.env.WHITECHAIN_RPC || 'https://rpc.testnet.whitechain.io';
const USDT_ADDR = '0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7';
const HOLDER = process.env.USDT_HOLDER || '0xA1616Fe9624B64eF2Dddc8ccAc735bAA234CEbF7';

// EDR doesn't know chain 1874, so tell it which EVM rules apply. Whitechain
// Sepolia runs Prague (OP Stack Isthmus) from genesis; L1 rules are enough for
// these calls (no deposit transactions involved).
const c = await chain(
  { type: 'edr-simulated', chainType: 'l1', chainId: 1874, hardfork: 'prague', forking: { url: RPC } },
  { chainDescriptors: { 1874: { name: 'Whitechain Sepolia', chainType: 'l1', hardforkHistory: { prague: { blockNumber: 0 } } } } },
);
const [payee, payer] = c.accounts;
const usdt = {
  address: USDT_ADDR,
  abi: parseAbi([
    'function name() view returns (string)',
    'function decimals() view returns (uint8)',
    'function balanceOf(address) view returns (uint256)',
    'function nonces(address) view returns (uint256)',
    'function DOMAIN_SEPARATOR() view returns (bytes32)',
    'function transfer(address,uint256) returns (bool)',
    'function approve(address,uint256) returns (bool)',
  ]),
};
const name = await read(c, usdt, 'name');
console.log('fork of chain', c.chainId, 'USDT name:', name, 'decimals:', await read(c, usdt, 'decimals'));

// fund the test payer with 50 USDT from an impersonated holder (fork only)
await c.test.impersonateAccount({ address: HOLDER });
await c.test.setBalance({ address: HOLDER, value: 10n ** 18n });
await send(c, HOLDER, usdt, 'transfer', [payer, 50_000_000n]);

const pr = await deploy(c, payee, 'GlyfPayRequest');
const zero = '0x0000000000000000000000000000000000000000';

// 1) approve + pay
let rc = await send(c, payee, pr, 'createRequest', [USDT_ADDR, 20_000_000n, 'fork: approve path', zero, 0n]);
let id = parseEventLogs({ abi: pr.abi, logs: rc.logs, eventName: 'RequestCreated' })[0].args.requestId;
const b0 = await read(c, usdt, 'balanceOf', [payee]);
await send(c, payer, usdt, 'approve', [pr.address, 20_000_000n]);
rc = await send(c, payer, pr, 'pay', [id]);
assert.equal(parseEventLogs({ abi: pr.abi, logs: rc.logs, eventName: 'Receipt' }).length, 1);
assert.equal(await read(c, usdt, 'balanceOf', [payee]), b0 + 20_000_000n);
console.log('approve + pay: OK, gas', rc.gasUsed);

// 2) payWithPermit (EIP-2612 on TetherTokenV2: domain name = token name, version "1")
rc = await send(c, payee, pr, 'createRequest', [USDT_ADDR, 10_000_000n, 'fork: permit path', payer, 0n]);
id = parseEventLogs({ abi: pr.abi, logs: rc.logs, eventName: 'RequestCreated' })[0].args.requestId;
const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
const nonce = await read(c, usdt, 'nonces', [payer]);
const domain = { name, version: '1', chainId: 1874, verifyingContract: USDT_ADDR };
const { hashDomain } = await import('viem');
const expectedSep = hashDomain({ domain, types: { EIP712Domain: [
  { name: 'name', type: 'string' }, { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' }, { name: 'verifyingContract', type: 'address' }] } });
assert.equal(await read(c, usdt, 'DOMAIN_SEPARATOR'), expectedSep, 'permit domain is {name, "1", 1874, token}');
const sig = await c.wallet(payer).signTypedData({
  domain,
  types: { Permit: [
    { name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' }, { name: 'deadline', type: 'uint256' }] },
  primaryType: 'Permit',
  message: { owner: payer, spender: pr.address, value: 10_000_000n, nonce, deadline },
});
const { r, s, v, yParity } = parseSignature(sig);
rc = await send(c, payer, pr, 'payWithPermit', [id, deadline, Number(v ?? BigInt(27 + yParity)), r, s]);
assert.equal((await read(c, pr, 'getRequest', [id])).status, 2);
console.log('payWithPermit: OK, gas', rc.gasUsed);

// 3) refund part of request 1 back to the payer
await send(c, payee, usdt, 'approve', [pr.address, 5_000_000n]);
rc = await send(c, payee, pr, 'refund', [1n, 5_000_000n]);
assert.equal(parseEventLogs({ abi: pr.abi, logs: rc.logs, eventName: 'Refunded' })[0].args.totalRefunded, 5_000_000n);
console.log('refund 5 of 20: OK');
console.log('fork test passed against the real Whitechain Sepolia test USDT');
process.exit(0);
