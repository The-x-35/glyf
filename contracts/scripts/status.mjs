// Shows the throwaway deployer balance and what the deploy will cost (read-only).
import fs from 'node:fs';
import { createPublicClient, http, formatEther, formatGwei } from 'viem';
import { whitechainSepolia } from './whitechain.mjs';
const pub = createPublicClient({ chain: whitechainSepolia, transport: http() });
const addr = fs.readFileSync(new URL('../.deployer-address', import.meta.url), 'utf8').trim();
const art = JSON.parse(fs.readFileSync(new URL('../out/GlyfPayRequest.json', import.meta.url), 'utf8'));
const gas = await pub.estimateGas({ account: addr, data: art.bytecode });
const gp = await pub.getGasPrice();
console.log('balance', formatEther(await pub.getBalance({ address: addr })), 'WBT; deploy gas', gas, 'gasPrice', formatGwei(gp), 'gwei; cost ~', formatEther(gas * gp), 'WBT');
