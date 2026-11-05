// Makes the throwaway 32-byte VAULT SECRET in arkiv/.key (mode 600, gitignored).
// The Arkiv owner key is derived from it exactly as the phone does (DESIGN.md),
// so this one file stands in for the iCloud Keychain item. Never printed.
// Prints only the derived owner ADDRESS, which needs tGLM from the faucet.
import fs from 'node:fs';
import crypto from 'node:crypto';
import { bytesToHex, hexToBytes } from 'viem';
import { deriveKeys } from './vault.mjs';

const p = new URL('./.key', import.meta.url);
if (!fs.existsSync(p)) {
  fs.writeFileSync(p, bytesToHex(crypto.randomBytes(32)) + '\n', { mode: 0o600 });
  fs.chmodSync(p, 0o600);
  console.log('new vault secret written to arkiv/.key');
}
const { owner } = deriveKeys(hexToBytes(fs.readFileSync(p, 'utf8').trim()));
fs.writeFileSync(new URL('./.owner-address', import.meta.url), owner + '\n');
console.log(`Arkiv owner address ${owner} (fund it with tGLM at https://hub.arkiv.network/faucet)`);
