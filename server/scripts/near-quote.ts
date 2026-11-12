/**
 * A live NEAR Intents quote for a typed phrase, the way the Glyf keyboard
 * reads it, without a phone or a Glyf session:
 *
 *   cd server && npm install
 *   npm run near:quote -- "swap 20 usdc on base to sol"
 *   npm run near:quote -- "send 5 usdc to illia.near"
 *   npm run near:quote -- "pay bob.near 10 usdc with sol" --json
 *
 * It calls 1Click (https://1click.chaindefuser.com, keyless) for a DRY quote:
 * a price and a time, no deposit address, nothing moves. A phrase with a
 * recipient also runs Guard's checks (lib/nearguard.ts), which asks NEAR RPC
 * whether a .near account exists. No .env is read: nothing here needs a key.
 */
import { nearRpc } from "../src/lib/names.js";
import { guardRecipient } from "../src/lib/nearguard.js";
import { IntentsError, NearIntents, nearChainOf } from "../src/lib/nearintents.js";
import { parseNearPhrase } from "../src/lib/nearphrase.js";

const args = process.argv.slice(2);
const json = args.includes("--json");
const phrase = args.filter(a => a !== "--json").join(" ").trim();

if (!phrase) {
  console.error('Usage: npm run near:quote -- "swap 20 usdc on base to sol" [--json]');
  process.exit(2);
}

const read = parseNearPhrase(phrase);
if (!read) {
  console.error(`Glyf doesn't read "${phrase}" as a NEAR Intents trade.`);
  console.error('Try "swap 20 usdc on base to sol", "move 50 usdc from base to solana" or "send 5 usdc to illia.near".');
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
