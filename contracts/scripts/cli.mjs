// Small helper for testing the deployed contract on Whitechain Sepolia.
//   node scripts/cli.mjs create <amountUSDT> "<memo>" [payer] [expiresInHours]
//       (payee = the deployer key; prints the glyf:// and https request links)
//   node scripts/cli.mjs show <id>
//   node scripts/cli.mjs link <id>
// Paying is the phone's job (the payer's own wallet signs approve + pay, or a
// permit + payWithPermit), so there is no "pay" command here.
import fs from 'node:fs';
import path from 'node:path';
import { createPublicClient, createWalletClient, http, parseEventLogs, parseUnits, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { whitechainSepolia, EXPLORER, TEST_USDT } from './whitechain.mjs';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const dep = JSON.parse(fs.readFileSync(path.join(root, 'deployments', 'whitechain-sepolia.json'), 'utf8'));
const abi = JSON.parse(fs.readFileSync(path.join(root, 'abi', 'GlyfPayRequest.json'), 'utf8'));
const pub = createPublicClient({ chain: whitechainSepolia, transport: http() });
const STATUS = ['None', 'Open', 'Paid', 'Cancelled', 'Refunded'];

export const links = (contract, id) => {
  const q = `chain=1874&contract=${contract}&id=${id}`;
  return { app: `glyf://pay-request?${q}`, web: `https://www.tryglyf.com/pay?${q}` };
};

const [cmd, ...a] = process.argv.slice(2);
if (cmd === 'create') {
  const account = privateKeyToAccount(fs.readFileSync(path.join(root, '.deployer.key'), 'utf8').trim());
  const wallet = createWalletClient({ chain: whitechainSepolia, transport: http(), account });
  const amount = parseUnits(a[0] ?? '1', 6);
  const memo = a[1] ?? '';
  const payer = a[2] && a[2] !== '-' ? a[2] : '0x0000000000000000000000000000000000000000';
  const expiresAt = a[3] ? BigInt(Math.floor(Date.now() / 1000) + Number(a[3]) * 3600) : 0n;
  const hash = await wallet.writeContract({ address: dep.address, abi, functionName: 'createRequest', args: [TEST_USDT, amount, memo, payer, expiresAt] });
  const rcpt = await pub.waitForTransactionReceipt({ hash });
  const [ev] = parseEventLogs({ abi, logs: rcpt.logs, eventName: 'RequestCreated' });
  console.log(`request ${ev.args.requestId} created: ${EXPLORER}/tx/${hash}`);
  console.log(links(dep.address, ev.args.requestId));
} else if (cmd === 'show') {
  const r = await pub.readContract({ address: dep.address, abi, functionName: 'getRequest', args: [BigInt(a[0])] });
  console.log({ ...r, status: STATUS[r.status], amount: formatUnits(r.amount, 6), refunded: formatUnits(r.refunded, 6) });
} else if (cmd === 'link') {
  console.log(links(dep.address, a[0]));
} else {
  console.log('usage: node scripts/cli.mjs create <amount> "<memo>" [payer|-] [hours] | show <id> | link <id>');
}
