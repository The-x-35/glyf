import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { parseEventLogs, parseSignature } from 'viem';
import { chain, deploy, send, reverts, read } from './helpers.mjs';

const ST = { None: 0, Open: 1, Paid: 2, Cancelled: 3, Refunded: 4 };
const USDT = (n) => BigInt(Math.round(n * 1e6));

let c, payee, payer, other, pr, usdt;

before(async () => {
  c = await chain();
  [payee, payer, other] = c.accounts;
  pr = await deploy(c, payee, 'GlyfPayRequest');
  usdt = await deploy(c, payee, 'MockUSDTNoBool');
  for (const a of [payee, payer, other]) await send(c, a, usdt, 'mint', [a, USDT(1000)]);
});

async function create(from, { amount = USDT(20), memo = 'dinner', namedPayer = '0x0000000000000000000000000000000000000000', expiresAt = 0n, token = usdt.address } = {}) {
  const rcpt = await send(c, from, pr, 'createRequest', [token, amount, memo, namedPayer, expiresAt]);
  const [ev] = parseEventLogs({ abi: pr.abi, logs: rcpt.logs, eventName: 'RequestCreated' });
  return ev.args.requestId;
}
const bal = (a) => read(c, usdt, 'balanceOf', [a]);
const now = async () => (await c.pub.getBlock()).timestamp;

test('pay with approve on a token that returns no bool: funds move payer -> payee, Receipt emitted', async () => {
  const id = await create(payee, { memo: 'tacos 🌮' });
  const r0 = await read(c, pr, 'getRequest', [id]);
  assert.equal(r0.status, ST.Open);
  assert.equal(r0.payee.toLowerCase(), payee);
  assert.equal(await read(c, pr, 'canPay', [id, payer]), true);
  assert.equal(await read(c, pr, 'canPay', [id, payee]), false);

  const [b0p, b0q] = [await bal(payer), await bal(payee)];
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  const rcpt = await send(c, payer, pr, 'pay', [id]);
  assert.equal(await bal(payer), b0p - USDT(20));
  assert.equal(await bal(payee), b0q + USDT(20));
  assert.equal(await bal(pr.address), 0n, 'contract never holds funds');

  const [ev] = parseEventLogs({ abi: pr.abi, logs: rcpt.logs, eventName: 'Receipt' });
  assert.equal(ev.args.requestId, id);
  assert.equal(ev.args.payer.toLowerCase(), payer);
  assert.equal(ev.args.payee.toLowerCase(), payee);
  assert.equal(ev.args.token.toLowerCase(), usdt.address.toLowerCase());
  assert.equal(ev.args.amount, USDT(20));
  assert.equal(ev.args.memo, 'tacos 🌮');
  const blk = await c.pub.getBlock({ blockNumber: rcpt.blockNumber });
  assert.equal(ev.args.timestamp, blk.timestamp);

  const r1 = await read(c, pr, 'getRequest', [id]);
  assert.equal(r1.status, ST.Paid);
  assert.equal(r1.paidBy.toLowerCase(), payer);
  assert.equal(r1.paidAt, blk.timestamp);

  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await reverts(c, payer, pr, 'pay', [id], 'NotOpen'); // no double pay
});

test('createRequest validation', async () => {
  const zero = '0x0000000000000000000000000000000000000000';
  await reverts(c, payee, pr, 'createRequest', [usdt.address, 0n, 'x', zero, 0n], 'ZeroAmount');
  await reverts(c, payee, pr, 'createRequest', [other, 1n, 'x', zero, 0n], 'NotAToken');
  await reverts(c, payee, pr, 'createRequest', [usdt.address, 1n, 'x'.repeat(141), zero, 0n], 'MemoTooLong');
  await reverts(c, payee, pr, 'createRequest', [usdt.address, 1n, 'x', zero, (await now()) - 1n], 'AlreadyExpired');
  await reverts(c, payee, pr, 'createRequest', [usdt.address, 1n, 'x', payee, 0n], 'PayerIsPayee');
  const id = await create(payee, { memo: 'x'.repeat(140) });
  assert.equal((await read(c, pr, 'getRequest', [id])).memo.length, 140);
  assert.equal(await read(c, pr, 'requestCount'), id);
  assert.equal((await read(c, pr, 'getRequest', [id + 100n])).status, ST.None);
  await reverts(c, payer, pr, 'pay', [id + 100n], 'UnknownRequest');
});

test('named payer: only that address can pay', async () => {
  const id = await create(payee, { namedPayer: payer });
  await send(c, other, usdt, 'approve', [pr.address, USDT(20)]);
  await reverts(c, other, pr, 'pay', [id], 'NotNamedPayer');
  assert.equal(await read(c, pr, 'canPay', [id, other]), false);
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await send(c, payer, pr, 'pay', [id]);
  assert.equal((await read(c, pr, 'getRequest', [id])).status, ST.Paid);
  await send(c, other, usdt, 'approve', [pr.address, 0n]);
});

test('payee cannot pay their own open request', async () => {
  const id = await create(payee);
  await send(c, payee, usdt, 'approve', [pr.address, USDT(20)]);
  await reverts(c, payee, pr, 'pay', [id], 'PayerIsPayee');
  await send(c, payee, usdt, 'approve', [pr.address, 0n]);
});

test('expiry: payable up to expiresAt, not after', async () => {
  const t = await now();
  const id = await create(payee, { expiresAt: t + 3600n });
  await c.test.increaseTime({ seconds: 3601 });
  await c.test.mine({ blocks: 1 });
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await reverts(c, payer, pr, 'pay', [id], 'Expired');
  assert.equal(await read(c, pr, 'canPay', [id, payer]), false);
  await send(c, payer, usdt, 'approve', [pr.address, 0n]);
});

test('missing allowance or balance: payment fails and request stays open', async () => {
  const id = await create(payee, { amount: USDT(5000) }); // payer has < 5000
  await send(c, payer, usdt, 'approve', [pr.address, USDT(5000)]);
  await reverts(c, payer, pr, 'pay', [id], 'TokenTransferFailed');
  const id2 = await create(payee);
  await send(c, payer, usdt, 'approve', [pr.address, USDT(1)]);
  await reverts(c, payer, pr, 'pay', [id2], 'TokenTransferFailed');
  assert.equal((await read(c, pr, 'getRequest', [id2])).status, ST.Open);
  await send(c, payer, usdt, 'approve', [pr.address, 0n]);
});

test('cancel: payee only, open only; a cancelled request cannot be paid', async () => {
  const id = await create(payee);
  await reverts(c, other, pr, 'cancel', [id], 'NotPayee');
  const rcpt = await send(c, payee, pr, 'cancel', [id]);
  const [ev] = parseEventLogs({ abi: pr.abi, logs: rcpt.logs, eventName: 'RequestCancelled' });
  assert.equal(ev.args.requestId, id);
  assert.equal((await read(c, pr, 'getRequest', [id])).status, ST.Cancelled);
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await reverts(c, payer, pr, 'pay', [id], 'NotOpen');
  await reverts(c, payee, pr, 'cancel', [id], 'NotOpen');
  await send(c, payer, usdt, 'approve', [pr.address, 0n]);

  const paid = await create(payee);
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await send(c, payer, pr, 'pay', [paid]);
  await reverts(c, payee, pr, 'cancel', [paid], 'NotOpen');
});

test('refund: part, then the rest; never more than paid; payee only', async () => {
  const id = await create(payee);
  await reverts(c, payee, pr, 'refund', [id, 1n], 'NotPaid');
  await send(c, payer, usdt, 'approve', [pr.address, USDT(20)]);
  await send(c, payer, pr, 'pay', [id]);

  await reverts(c, other, pr, 'refund', [id, 1n], 'NotPayee');
  await reverts(c, payee, pr, 'refund', [id, 0n], 'ZeroAmount');
  await reverts(c, payee, pr, 'refund', [id, USDT(20) + 1n], 'RefundTooLarge');
  await reverts(c, payee, pr, 'refund', [id, USDT(5)], 'TokenTransferFailed'); // no allowance yet

  await send(c, payee, usdt, 'approve', [pr.address, USDT(20)]);
  const b0 = await bal(payer);
  const r1 = await send(c, payee, pr, 'refund', [id, USDT(5)]);
  const [ev1] = parseEventLogs({ abi: pr.abi, logs: r1.logs, eventName: 'Refunded' });
  assert.equal(ev1.args.amount, USDT(5));
  assert.equal(ev1.args.totalRefunded, USDT(5));
  assert.equal(ev1.args.payer.toLowerCase(), payer);
  assert.equal(await bal(payer), b0 + USDT(5));
  assert.equal((await read(c, pr, 'getRequest', [id])).status, ST.Paid);

  await reverts(c, payee, pr, 'refund', [id, USDT(15) + 1n], 'RefundTooLarge');
  await send(c, payee, pr, 'refund', [id, USDT(15)]);
  const r = await read(c, pr, 'getRequest', [id]);
  assert.equal(r.status, ST.Refunded);
  assert.equal(r.refunded, USDT(20));
  assert.equal(await bal(payer), b0 + USDT(20));
  await reverts(c, payee, pr, 'refund', [id, 1n], 'NotPaid');
});

async function signPermit(owner, value, deadline) {
  const nonce = await read(c, usdt, 'nonces', [owner]);
  const sig = await c.wallet(owner).signTypedData({
    domain: { name: 'Tether USD', version: '1', chainId: c.chainId, verifyingContract: usdt.address },
    types: { Permit: [
      { name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' }, { name: 'deadline', type: 'uint256' },
    ] },
    primaryType: 'Permit',
    message: { owner, spender: pr.address, value, nonce, deadline },
  });
  const { r, s, v, yParity } = parseSignature(sig);
  return { v: Number(v ?? BigInt(27 + yParity)), r, s };
}

test('payWithPermit: one transaction, no approve', async () => {
  const id = await create(payee);
  assert.equal(await read(c, usdt, 'allowance', [payer, pr.address]), 0n);
  const deadline = (await now()) + 600n;
  const { v, r, s } = await signPermit(payer, USDT(20), deadline);
  const b0 = await bal(payee);
  const rcpt = await send(c, payer, pr, 'payWithPermit', [id, deadline, v, r, s]);
  assert.equal(await bal(payee), b0 + USDT(20));
  assert.equal(parseEventLogs({ abi: pr.abi, logs: rcpt.logs, eventName: 'Receipt' }).length, 1);
});

test('payWithPermit still pays if someone front-ran the permit', async () => {
  const id = await create(payee);
  const deadline = (await now()) + 600n;
  const { v, r, s } = await signPermit(payer, USDT(20), deadline);
  // attacker submits the same permit first
  await send(c, other, usdt, 'permit', [payer, pr.address, USDT(20), deadline, v, r, s]);
  await send(c, payer, pr, 'payWithPermit', [id, deadline, v, r, s]);
  assert.equal((await read(c, pr, 'getRequest', [id])).status, ST.Paid);
});

test('payWithPermit with a bad signature and no allowance fails cleanly', async () => {
  const id = await create(payee);
  const deadline = (await now()) + 600n;
  const { v, r, s } = await signPermit(other, USDT(20), deadline); // signed by the wrong account
  await reverts(c, payer, pr, 'payWithPermit', [id, deadline, v, r, s], 'TokenTransferFailed');
  assert.equal((await read(c, pr, 'getRequest', [id])).status, ST.Open);
});

test('tokens returning false or malformed data are rejected', async () => {
  const f = await deploy(c, payee, 'MockFalseToken');
  const sh = await deploy(c, payee, 'MockShortReturnToken');
  const id1 = await create(payee, { token: f.address });
  const id2 = await create(payee, { token: sh.address });
  await reverts(c, payer, pr, 'pay', [id1], 'TokenTransferFailed');
  await reverts(c, payer, pr, 'pay', [id2], 'TokenTransferFailed');
});

test('reentrancy from a token callback is blocked', async () => {
  const evil = await deploy(c, payee, 'MockReentrantToken');
  const a = await create(payee, { token: evil.address });
  const b = await create(payee, { token: evil.address });
  await send(c, payer, evil, 'arm', [pr.address, b, false]);
  await reverts(c, payer, pr, 'pay', [a], 'TokenTransferFailed'); // inner pay() hits the lock -> call fails
  assert.equal((await read(c, pr, 'getRequest', [a])).status, ST.Open);
  assert.equal((await read(c, pr, 'getRequest', [b])).status, ST.Open);

  // refund path: pay a cleanly, then arm a refund re-entry
  await send(c, payer, evil, 'arm', ['0x0000000000000000000000000000000000000000', 0n, false]);
  await send(c, payer, pr, 'pay', [a]);
  await send(c, payee, evil, 'arm', [pr.address, a, true]);
  await reverts(c, payee, pr, 'refund', [a, 1n], 'TokenTransferFailed');
  assert.equal((await read(c, pr, 'getRequest', [a])).refunded, 0n);
});
