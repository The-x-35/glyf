// Shared setup: an in-process Hardhat (EDR) chain driven with plain viem.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHardhatRuntimeEnvironment } from 'hardhat/hre';
import { createPublicClient, createWalletClient, createTestClient, custom } from 'viem';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
export const artifact = (name) => JSON.parse(fs.readFileSync(path.join(root, 'out', `${name}.json`), 'utf8'));

export async function chain(networkConfig, extraConfig = {}) {
  const hre = await createHardhatRuntimeEnvironment(networkConfig ? { ...extraConfig, networks: { sim: networkConfig } } : {});
  const conn = networkConfig ? await hre.network.create('sim') : await hre.network.create();
  const transport = custom(conn.provider, { retryCount: 0 });
  const chainId = Number(await conn.provider.request({ method: 'eth_chainId' }));
  const viemChain = {
    id: chainId, name: 'sim', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: ['http://unused'] } },
  };
  const pub = createPublicClient({ chain: viemChain, transport, pollingInterval: 5 });
  const test = createTestClient({ chain: viemChain, transport, mode: 'hardhat' });
  const accounts = await conn.provider.request({ method: 'eth_accounts' });
  const wallet = (account) => createWalletClient({ chain: viemChain, transport, account });
  return { conn, pub, test, accounts, wallet, chainId, provider: conn.provider };
}

export async function deploy(c, from, name, args = []) {
  const a = artifact(name);
  const hash = await c.wallet(from).deployContract({ abi: a.abi, bytecode: a.bytecode, args });
  const rcpt = await c.pub.waitForTransactionReceipt({ hash });
  assert.equal(rcpt.status, 'success');
  return { address: rcpt.contractAddress, abi: a.abi };
}

/// Send a tx and return the receipt (asserting success).
export async function send(c, from, contract, functionName, args = []) {
  const hash = await c.wallet(from).writeContract({ address: contract.address, abi: contract.abi, functionName, args });
  const rcpt = await c.pub.waitForTransactionReceipt({ hash });
  assert.equal(rcpt.status, 'success', `${functionName} failed`);
  return rcpt;
}

/// Expect a call from `from` to revert with custom error `errorName`.
export async function reverts(c, from, contract, functionName, args, errorName) {
  try {
    await c.pub.simulateContract({ account: from, address: contract.address, abi: contract.abi, functionName, args });
  } catch (e) {
    let cur = e;
    while (cur) {
      if (cur.data?.errorName) {
        assert.equal(cur.data.errorName, errorName, `expected ${errorName}, got ${cur.data.errorName}`);
        return;
      }
      cur = cur.cause;
    }
    if (errorName && !String(e.message).includes(errorName)) throw e;
    return;
  }
  assert.fail(`${functionName} did not revert (expected ${errorName})`);
}

export const read = (c, contract, functionName, args = []) =>
  c.pub.readContract({ address: contract.address, abi: contract.abi, functionName, args });
