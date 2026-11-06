// Prints function selectors, event topic0s and error selectors (for the Dart/Swift ports).
import fs from 'node:fs';
import { toFunctionSelector, toEventSelector } from 'viem';
import { formatAbiItem } from 'viem/utils';
const abi = JSON.parse(fs.readFileSync(new URL('../abi/GlyfPayRequest.json', import.meta.url), 'utf8'));
for (const i of abi) if (i.type === 'function') console.log(`| \`${toFunctionSelector(i)}\` | \`${formatAbiItem(i)}\` |`);
for (const i of abi) if (i.type === 'event') console.log(`| \`${toEventSelector(i)}\` | \`${formatAbiItem(i)}\` |`);
for (const i of abi) if (i.type === 'error') console.log(`| \`${toFunctionSelector({ ...i, type: 'function', outputs: [] })}\` | \`${i.name}()\` |`);
