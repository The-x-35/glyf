// Deploys GlyfPayRequest to Whitechain Sepolia (chain 1874) from the
// throwaway key in contracts/.deployer.key, records the deployment in
// deployments/whitechain-sepolia.json, then verifies it on the explorer.
//   npm run deploy            (build + deploy + verify)
import fs from 'node:fs';
import path from 'node:path';
import { createPublicClient, createWalletClient, http, formatEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { whitechainSepolia, EXPLORER, TEST_USDT } from './whitechain.mjs';
import { verify } from './verify.mjs';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const keyPath = path.join(root, '.deployer.key');
if (!fs.existsSync(keyPath)) { console.error('no .deployer.key; run `npm run keygen` first'); process.exit(1); }
const account = privateKeyToAccount(fs.readFileSync(keyPath, 'utf8').trim());
const art = JSON.parse(fs.readFileSync(path.join(root, 'out', 'GlyfPayRequest.json'), 'utf8'));

const pub = createPublicClient({ chain: whitechainSepolia, transport: http() });
const wallet = createWalletClient({ chain: whitechainSepolia, transport: http(), account });

const chainId = await pub.getChainId();
if (chainId !== 1874) throw new Error(`RPC is chain ${chainId}, expected 1874 (Whitechain Sepolia)`);
const bal = await pub.getBalance({ address: account.address });
console.log(`deployer ${account.address} has ${formatEther(bal)} WBT on Whitechain Sepolia`);
if (bal === 0n) { console.error('no test WBT: fund it at https://faucet.testnet.whitechain.io'); process.exit(1); }

const hash = await wallet.deployContract({ abi: art.abi, bytecode: art.bytecode, args: [] });
console.log(`deploy tx ${EXPLORER}/tx/${hash}`);
const rcpt = await pub.waitForTransactionReceipt({ hash });
if (rcpt.status !== 'success') throw new Error('deploy reverted');
const address = rcpt.contractAddress;
console.log(`GlyfPayRequest at ${EXPLORER}/address/${address} (block ${rcpt.blockNumber}, gas ${rcpt.gasUsed})`);

fs.mkdirSync(path.join(root, 'deployments'), { recursive: true });
const out = {
  chainId: 1874, network: 'Whitechain Sepolia', contract: 'GlyfPayRequest', address,
  deployTx: hash, block: Number(rcpt.blockNumber), deployer: account.address,
  testUsdt: TEST_USDT, compiler: 'v0.8.30+commit.73712a01', optimizerRuns: 200, evmVersion: 'prague',
  deployedAt: new Date().toISOString(),
};
fs.writeFileSync(path.join(root, 'deployments', 'whitechain-sepolia.json'), JSON.stringify(out, null, 2) + '\n');

// Blockscout indexes new contracts within a few seconds; give it a moment.
await new Promise((r) => setTimeout(r, 8000));
await verify(address);
