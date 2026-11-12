/**
 * A live NEAR Intents quote for a typed phrase, the way the Glyf keyboard
 * reads it, without a phone or a Glyf session:
 *
 *   cd server && npm install
 *   npm run near:quote -- "swap 20 usdc on base to sol"
 *   npm run near:quote -- "send 5 usdc to illia.near"
 *   npm run near:quote -- "pay bob.near 10 usdc with sol" --json
 *   npm run near:quote -- "put 50 usdc to work"        (Earn: into a vault)
 *   npm run near:quote -- "take 20 usdc out of earn"   (Earn: back out)
 *
 * It calls 1Click (https://1click.chaindefuser.com, keyless) for a DRY quote:
 * a price and a time, no deposit address, nothing moves. A phrase with a
 * recipient also runs Guard's checks (lib/nearguard.ts), which asks NEAR RPC
 * whether a .near account exists. An Earn phrase quotes the vault's receipt
 * token (lib/nearearn.ts) and reads the vault's APY from its protocol's
 * public API (Morpho, Kamino). No .env is read: nothing here needs a key.
 */
import { nearRpc } from "../src/lib/names.js";
import { EarnRates, earnQuote, earnVaults } from "../src/lib/nearearn.js";
import { guardRecipient } from "../src/lib/nearguard.js";
import { IntentsError, NearIntents, nearChainOf } from "../src/lib/nearintents.js";
import { parseEarnPhrase, parseNearPhrase } from "../src/lib/nearphrase.js";

const args = process.argv.slice(2);
const json = args.includes("--json");
const phrase = args.filter(a => a !== "--json").join(" ").trim();

if (!phrase) {
  console.error('Usage: npm run near:quote -- "swap 20 usdc on base to sol" [--json]');
  process.exit(2);
}

const earn = parseEarnPhrase(phrase);
if (earn) {
  const chainName = (key: string) => nearChainOf(key)?.name ?? key;
  try {
    const intents = new NearIntents();
    const rates = new EarnRates();
    if (!earn.amount) {
      // "take my usdc out of earn": everything. The app sends its share
      // balance as `shares`; without a wallet, here are the vaults.
      const vaults = (await earnVaults(intents, rates)).filter(v => v.underlying === earn.coin);
      if (json) console.log(JSON.stringify({ phrase, read: earn, vaults }, null, 2));
      else {
        console.log(`"${phrase}"`);
        console.log(`  earn ${earn.direction}: all your ${earn.coin}. The app sends its share balance (shares) to POST /near/earn/quote.`);
        for (const v of vaults) console.log(`  ${v.default ? "*" : " "} ${v.name} (${v.protocol}, ${v.chainName}) ${v.receipt}${v.apy !== null ? `, ${v.apy}% APY (${v.apySource})` : ""}`);
      }
      process.exit(0);
    }
    const quote = await earnQuote(intents, rates, { direction: earn.direction, coin: earn.coin, chain: earn.chain, amount: earn.amount });
    if (json) {
      console.log(JSON.stringify({ phrase, read: earn, quote }, null, 2));
    } else {
      const v = quote.vault;
      const dollars = (x: string | null) => x === null ? "" : ` ($${x})`;
      console.log(`"${phrase}"`);
      console.log(`  earn ${earn.direction === "in" ? "in: put" : "out: get back"} ${earn.amount} ${earn.coin}`);
      console.log(`  Vault        ${v.name} (${v.protocol} on ${v.chainName}), shares ${v.receipt}`);
      console.log(`  APY          ${v.apy !== null ? `${v.apy}% (${v.apyBasis}, from ${v.apySource})` : "not published by a public API"}`);
      console.log(`  Venue        ${quote.venue} 1Click Earn (dry quote: nothing moves)`);
      console.log(`  You pay      ${quote.amountIn} ${quote.sell.symbol} on ${chainName(quote.sell.chain)}${dollars(quote.amountInUsd)}`);
      console.log(`  You get      ${quote.amountOut} ${quote.buy.symbol} on ${chainName(quote.buy.chain)}${dollars(quote.amountOutUsd)}`);
      console.log(`  In words     ${quote.words}`);
      if (quote.timeSeconds !== null) console.log(`  Time         about ${quote.timeSeconds} s after the deposit confirms`);
      console.log(`  Assets       ${quote.sell.assetId} -> ${quote.buy.assetId}`);
    }
  } catch (err) {
    console.error(err instanceof IntentsError ? err.message : `NEAR Intents didn't answer: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
  process.exit(0);
}

const read = parseNearPhrase(phrase);
if (!read) {
  console.error(`Glyf doesn't read "${phrase}" as a NEAR Intents trade.`);
  console.error('Try "swap 20 usdc on base to sol", "move 50 usdc from base to solana", "send 5 usdc to illia.near" or "put 50 usdc to work".');
  process.exit(2);
}

const chainName = (key: string) => nearChainOf(key)?.name ?? key;
const q = read.quote;

try {
  const intents = new NearIntents();
  // The recipient is only Guard's: a dry quote is priced with stand-ins.
  const { recipient, ...priced } = q;
  const quote = await intents.quote(priced);
  const guard = recipient ? await guardRecipient({ recipient, chain: nearChainOf(q.buyChain)!,
    amountInUsd: quote.amountInUsd === null ? null : Number(quote.amountInUsd) }, nearRpc()) : undefined;
  if (json) {
    console.log(JSON.stringify({ phrase, read, quote, ...(guard ? { guard } : {}) }, null, 2));
  } else {
    const dollars = (v: string | null) => v === null ? "" : ` ($${v})`;
    console.log(`"${phrase}"`);
    console.log(`  ${read.kind}: ${q.exact === "out" ? "they get" : "you pay"} ${q.amount} ${q.exact === "out" ? q.buy : q.sell}`
      + `${recipient ? `, to ${recipient}` : ""}`);
    console.log(`  Venue        ${quote.venue} (1Click, dry quote: nothing moves)`);
    console.log(`  You pay      ${quote.amountIn} ${quote.sell.symbol} on ${chainName(quote.sell.chain)}${dollars(quote.amountInUsd)}`);
    console.log(`  ${q.exact === "out" ? "They get" : "You get "}     ${quote.amountOut} ${quote.buy.symbol} on ${chainName(quote.buy.chain)}${dollars(quote.amountOutUsd)}`);
    console.log(`  At least     ${quote.minAmountOut} ${quote.buy.symbol} (${q.slippage ?? 1}% slippage)`);
    if (quote.timeSeconds !== null) console.log(`  Time         about ${quote.timeSeconds} s after the deposit confirms`);
    console.log(`  Assets       ${quote.sell.assetId} -> ${quote.buy.assetId}`);
    if (guard) {
      console.log(`  Guard        ${guard.level}`);
      for (const c of guard.checks) console.log(`    ${c.level.padEnd(5)} ${c.id}: ${c.text}`);
    }
  }
} catch (err) {
  console.error(err instanceof IntentsError ? err.message : `NEAR Intents didn't answer: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
}
