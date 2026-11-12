/**
 * A Sputnik DAO group pot, read live from NEAR RPC the way GET /near/pot
 * answers the app, without a phone or a Glyf session:
 *
 *   cd server && npm install
 *   npm run near:pot -- build.sputnik-dao.near
 *   npm run near:pot -- build.sputnik-dao.near "pay efiz.near $120 from the pot for catering"
 *   npm run near:pot -- build.sputnik-dao.near --json
 *
 * The first prints the pot's balance (NEAR, plus USDC/USDT held directly or
 * in NEAR Intents), its members, how many approvals a payout needs, and its
 * latest proposals with their votes. With a payout phrase it also prints
 * the Trezu link that proposes it and the raw add_proposal call. Only
 * function-call views: nothing is signed. No .env is read.
 */
import { parsePotPhrase } from "../src/lib/nearphrase.js";
import { PotError, Pots, proposeLink } from "../src/lib/sputnik.js";
import { parseUnits } from "viem";

const args = process.argv.slice(2);
const json = args.includes("--json");
const [dao, ...rest] = args.filter(a => a !== "--json");
const phrase = rest.join(" ").trim();

if (!dao) {
  console.error('Usage: npm run near:pot -- <name>.sputnik-dao.near ["pay bob.near $120 from the pot"] [--json]');
  process.exit(2);
}

try {
  const pot = await new Pots().pot(dao);
  const said = phrase ? parsePotPhrase(phrase) : null;
  if (phrase && said?.ask !== "pay") {
    console.error(`Glyf doesn't read "${phrase}" as a payout from the pot. Try "pay bob.near $120 from the pot".`);
    process.exit(2);
  }
  const link = said?.ask === "pay"
    ? proposeLink({ dao: pot.dao, to: said.payee, amount: said.amount, coin: said.coin, note: said.note }, parseUnits(pot.bond, 24).toString())
    : null;
  if (json) {
    console.log(JSON.stringify({ pot, ...(link ? { propose: link } : {}) }, null, 2));
    process.exit(0);
  }
  console.log(`${pot.name} (${pot.dao})${pot.purpose ? `: ${pot.purpose}` : ""}`);
  console.log(`  Holds        ${pot.balance.near} NEAR${pot.balance.tokens.map(t => ` · ${t.amount} ${t.symbol}${t.inIntents ? " (in NEAR Intents)" : ""}`).join("")}`);
  console.log(`  Members      ${pot.memberCount}: ${pot.members.slice(0, 8).join(", ")}${pot.memberCount > 8 ? ", …" : ""}`);
  console.log(`  Payouts pass ${pot.threshold ? `${pot.threshold.words} ${pot.threshold.role} members approve` : "by token weight"}; bond ${pot.bond} NEAR, ${pot.votingDays} days to vote`);
  console.log(`  Can propose  ${pot.proposers === "everyone" ? "anyone" : pot.proposers.slice(0, 8).join(", ")}`);
  console.log(`  Latest proposals (of ${pot.lastProposalId}):`);
  for (const p of pot.proposals) {
    const what = p.kind === "Transfer" && p.amount ? `${p.amount} ${p.coin} to ${p.receiver}` : p.kind;
    const need = p.approvalsNeeded !== null ? `, ${p.approvalsNeeded} more approvals needed` : "";
    console.log(`    #${p.id} ${p.status.padEnd(10)} ${what} · ${p.votes.approve} yes ${p.votes.reject} no${need}`);
    console.log(`         ${p.description.split("\n")[0].slice(0, 90)}`);
  }
  if (link) {
    console.log(`  Propose      ${link.text}`);
    console.log(`  Trezu        ${link.url}`);
    console.log(`               then type ${link.fill.amount} ${link.fill.coin}${link.fill.note ? ` and "${link.fill.note}"` : ""}; the members vote in Trezu`);
    console.log(`  Or sign      ${link.call.contract}.add_proposal ${JSON.stringify(link.call.args)} with ${pot.bond} NEAR attached`);
  }
} catch (err) {
  console.error(err instanceof PotError ? err.message : `NEAR didn't answer: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
}
