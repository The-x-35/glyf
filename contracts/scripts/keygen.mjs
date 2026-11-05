// Makes a fresh throwaway deployer key in contracts/.deployer.key (mode 600,
// gitignored) and writes only its ADDRESS to contracts/.deployer-address.
// The key is never printed. Refuses to overwrite an existing key.
import fs from 'node:fs';
import path from 'node:path';
import { generatePrivateKey, privateKeyToAddress } from 'viem/accounts';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const keyPath = path.join(root, '.deployer.key');
if (fs.existsSync(keyPath)) {
  const addr = privateKeyToAddress(fs.readFileSync(keyPath, 'utf8').trim());
  console.log(`key already exists; deployer address ${addr}`);
  process.exit(0);
}
const key = generatePrivateKey();
fs.writeFileSync(keyPath, key + '\n', { mode: 0o600 });
fs.chmodSync(keyPath, 0o600);
const addr = privateKeyToAddress(key);
fs.writeFileSync(path.join(root, '.deployer-address'), addr + '\n');
console.log(`new throwaway deployer address ${addr} (fund it at https://faucet.testnet.whitechain.io)`);
