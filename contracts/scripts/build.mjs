// Compiles contracts with solc-js (npm `solc`, pinned in package.json).
// Writes out/<Name>.json (abi + bytecode), out/GlyfPayRequest.input.json
// (standard JSON input of the deployable contract alone, used to verify on
// Blockscout) and abi/GlyfPayRequest.json (committed, for the phone app).
import fs from 'node:fs';
import path from 'node:path';
import solc from 'solc';

const root = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

export const SETTINGS = {
  optimizer: { enabled: true, runs: 200 },
  evmVersion: 'prague',
  metadata: { bytecodeHash: 'ipfs' },
  outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'] } },
};

function compile(sources) {
  const input = { language: 'Solidity', sources, settings: SETTINGS };
  const out = JSON.parse(solc.compile(JSON.stringify(input)));
  const errs = (out.errors || []).filter((e) => e.severity === 'error');
  for (const e of out.errors || []) console.error(e.formattedMessage);
  if (errs.length) process.exit(1);
  return { input, out };
}

const mainSources = { 'src/GlyfPayRequest.sol': { content: read('src/GlyfPayRequest.sol') } };
const { input: mainInput, out: mainOut } = compile(mainSources);
const { out: mockOut } = compile({ 'test/mocks/Mocks.sol': { content: read('test/mocks/Mocks.sol') } });

fs.mkdirSync(path.join(root, 'out'), { recursive: true });
fs.mkdirSync(path.join(root, 'abi'), { recursive: true });
for (const o of [mainOut, mockOut]) {
  for (const [file, cs] of Object.entries(o.contracts)) {
    for (const [name, c] of Object.entries(cs)) {
      fs.writeFileSync(path.join(root, 'out', `${name}.json`), JSON.stringify({
        contractName: name, sourceName: file, abi: c.abi,
        bytecode: '0x' + c.evm.bytecode.object, deployedBytecode: '0x' + c.evm.deployedBytecode.object,
      }, null, 2));
    }
  }
}
fs.writeFileSync(path.join(root, 'out', 'GlyfPayRequest.input.json'), JSON.stringify(mainInput));
const main = mainOut.contracts['src/GlyfPayRequest.sol'].GlyfPayRequest;
fs.writeFileSync(path.join(root, 'abi', 'GlyfPayRequest.json'), JSON.stringify(main.abi, null, 2) + '\n');
console.log(`compiled with solc ${solc.version()}; GlyfPayRequest runtime ${main.evm.deployedBytecode.object.length / 2} bytes`);
