// Verifies GlyfPayRequest on the Whitechain Sepolia Blockscout explorer with
// the exact standard JSON input that scripts/build.mjs compiled.
//   npm run verify -- 0xADDRESS     (defaults to deployments/whitechain-sepolia.json)
// Uses Blockscout's REST v2 endpoint
//   POST /api/v2/smart-contracts/{address}/verification/via/standard-input
// and falls back to the Etherscan-compatible
//   POST /api?module=contract&action=verifysourcecode  (what `forge --verifier blockscout` uses).
import fs from 'node:fs';
import path from 'node:path';
import { EXPLORER } from './whitechain.mjs';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const COMPILER = 'v0.8.30+commit.73712a01';
const NAME = 'GlyfPayRequest';
const FQN = 'src/GlyfPayRequest.sol:GlyfPayRequest';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function isVerified(address) {
  const r = await fetch(`${EXPLORER}/api/v2/smart-contracts/${address}`);
  if (!r.ok) return false;
  const j = await r.json();
  return Boolean(j.is_verified || j.is_fully_verified);
}

async function viaV2(address, input) {
  const form = new FormData();
  form.append('compiler_version', COMPILER);
  form.append('contract_name', NAME);
  form.append('license_type', 'mit');
  form.append('autodetect_constructor_args', 'true');
  form.append('files[0]', new Blob([input], { type: 'application/json' }), 'GlyfPayRequest.input.json');
  const r = await fetch(`${EXPLORER}/api/v2/smart-contracts/${address}/verification/via/standard-input`, { method: 'POST', body: form });
  const text = await r.text();
  console.log(`blockscout v2: HTTP ${r.status} ${text.slice(0, 300)}`);
  return r.ok;
}

async function viaEtherscanApi(address, input) {
  const body = new URLSearchParams({
    module: 'contract', action: 'verifysourcecode', codeformat: 'solidity-standard-json-input',
    contractaddress: address, contractname: FQN, compilerversion: COMPILER, sourceCode: input, licenseType: '3',
  });
  const r = await fetch(`${EXPLORER}/api`, { method: 'POST', body });
  const j = await r.json().catch(() => ({}));
  console.log(`etherscan-compatible: ${JSON.stringify(j).slice(0, 300)}`);
  if (j.status !== '1') return false;
  for (let i = 0; i < 20; i++) {
    await sleep(3000);
    const s = await (await fetch(`${EXPLORER}/api?module=contract&action=checkverifystatus&guid=${j.result}`)).json();
    console.log(`  status: ${s.result}`);
    if (/pass|already verified/i.test(s.result)) return true;
    if (/fail/i.test(s.result)) return false;
  }
  return false;
}

export async function verify(address) {
  const input = fs.readFileSync(path.join(root, 'out', 'GlyfPayRequest.input.json'), 'utf8');
  if (await isVerified(address)) { console.log('already verified'); return true; }
  await viaV2(address, input);
  for (let i = 0; i < 20; i++) {
    await sleep(3000);
    if (await isVerified(address)) { console.log(`verified: ${EXPLORER}/address/${address}?tab=contract`); return true; }
  }
  if (await viaEtherscanApi(address, input) && await isVerified(address)) {
    console.log(`verified: ${EXPLORER}/address/${address}?tab=contract`);
    return true;
  }
  console.error('verification not confirmed; check the explorer and rerun `npm run verify`');
  process.exitCode = 1;
  return false;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let address = process.argv[2];
  if (!address) {
    const f = path.join(root, 'deployments', 'whitechain-sepolia.json');
    if (!fs.existsSync(f)) { console.error('usage: npm run verify -- 0xADDRESS'); process.exit(1); }
    address = JSON.parse(fs.readFileSync(f, 'utf8')).address;
  }
  if (!fs.existsSync(path.join(root, 'out', 'GlyfPayRequest.input.json'))) {
    console.error('run `npm run build` first'); process.exit(1);
  }
  await verify(address);
}
