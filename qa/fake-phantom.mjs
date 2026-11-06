// A stand-in for Phantom on the iPhone simulator, where Phantom can't run.
// It answers Glyf's deeplinks the way Phantom does (NaCl box over x25519,
// base58 everywhere) with a throwaway wallet it keeps in the temp folder
// (glyf-fake-phantom.json). That wallet holds nothing, so a signed send
// reaches Solana and is turned down for want of SOL: the whole round trip
// runs, and no money can move.
//
// Debug builds log each Phantom link in pieces (GLYF_PHANTOM i/n …); this
// reads the latest one from the simulator's log, answers it and opens the
// answer in the simulator:
//
//   node qa/fake-phantom.mjs connect   # after tapping Connect Phantom
//   node qa/fake-phantom.mjs sign      # after Review in Phantom / Buy with Phantom
//   node qa/fake-phantom.mjs cancel    # answer anything with "cancelled" (4001)
//   node qa/fake-phantom.mjs message   # signMessage (a Flash order's message)
//   node qa/fake-phantom.mjs auto      # whatever the last link asks: sign or message
//
// A Flash order on Solana (Trade screen) asks for a setup transaction, then
// one message (two with an attached take-profit / stop-loss): run `auto`
// after each Phantom step; `--wait` first waits for a link newer than the
// last one answered.
//
// Needs tweetnacl, bs58 and @solana/web3.js:
//   cd qa && npm i --no-save tweetnacl bs58 @solana/web3.js
// SIM=<udid> picks the simulator (default: the booted one).
// FAKE_PHANTOM_STATE=<file> keeps the stand-in's keys there instead of the
// temp folder's glyf-fake-phantom.json.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import nacl from "tweetnacl";
import bs58 from "bs58";
import { Keypair, VersionedTransaction } from "@solana/web3.js";

const SIM = process.env.SIM ?? "booted";
const STATE = process.env.FAKE_PHANTOM_STATE ?? join(tmpdir(), "glyf-fake-phantom.json");

let state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, "utf8")) : null;
if (!state) {
  state = {
    encSecret: bs58.encode(nacl.box.keyPair().secretKey),
    walletSecret: bs58.encode(Keypair.generate().secretKey),
  };
  writeFileSync(STATE, JSON.stringify(state));
}
const enc = nacl.box.keyPair.fromSecretKey(bs58.decode(state.encSecret));
const wallet = Keypair.fromSecretKey(bs58.decode(state.walletSecret));

/** The latest Phantom link the app logged, put back together. */
function lastLink() {
  const log = execFileSync("xcrun", ["simctl", "spawn", SIM, "log", "show", "--last", "5m", "--style", "compact",
    "--predicate", 'process == "Runner" AND eventMessage CONTAINS "GLYF_PHANTOM"'], { encoding: "utf8" });
  let parts = {}, link = null;
  for (const line of log.split("\n")) {
    const m = line.match(/GLYF_PHANTOM (\d+)\/(\d+) (\S+)/);
    if (!m) continue;
    const [i, n] = [Number(m[1]), Number(m[2])];
    if (i === 0) parts = {};
    parts[i] = m[3];
    if (Object.keys(parts).length === n) link = Array.from({ length: n }, (_, k) => parts[k]).join("");
  }
  if (!link) throw new Error("No Phantom link in the last 5 minutes of the log (debug build?)");
  return new URL(link);
}

let mode = process.argv[2];
let link = lastLink();
if (process.argv.includes("--wait")) {
  // A link this stand-in already answered isn't answered twice.
  const until = Date.now() + 120_000;
  while (state.answered === link.searchParams.get("nonce")) {
    if (Date.now() > until) throw new Error("No new Phantom link in 2 minutes");
    await new Promise(r => setTimeout(r, 1500));
    link = lastLink();
  }
}
if (mode === "auto") {
  if (link.pathname.endsWith("/signMessage")) mode = "message";
  else if (link.pathname.endsWith("/signTransaction")) mode = "sign";
  else if (link.pathname.endsWith("/connect")) mode = "connect";
  else throw new Error(`Don't know how to answer ${link.pathname}`);
}
const p = link.searchParams;
const reply = new URL(p.get("redirect_link"));
const shared = nacl.box.before(bs58.decode(p.get("dapp_encryption_public_key")), enc.secretKey);
const seal = obj => {
  const nonce = nacl.randomBytes(24);
  reply.searchParams.set("nonce", bs58.encode(nonce));
  reply.searchParams.set("data", bs58.encode(nacl.box.after(Buffer.from(JSON.stringify(obj)), nonce, shared)));
};

if (mode === "connect") {
  if (!link.pathname.endsWith("/connect")) throw new Error(`The last link is ${link.pathname}, not a connect`);
  reply.searchParams.set("phantom_encryption_public_key", bs58.encode(enc.publicKey));
  seal({ public_key: wallet.publicKey.toBase58(), session: `fake-session-${Date.now()}` });
} else if (mode === "sign") {
  const opened = nacl.box.open.after(bs58.decode(p.get("payload")), bs58.decode(p.get("nonce")), shared);
  if (!opened) throw new Error("The request didn't open: it was sealed for another Phantom key");
  const request = JSON.parse(Buffer.from(opened).toString());
  const tx = VersionedTransaction.deserialize(bs58.decode(request.transaction));
  console.error(`signing ${tx.version === "legacy" ? "a legacy" : "a v0"} transaction, `
    + `${tx.message.compiledInstructions.length} instructions, fee payer ${tx.message.staticAccountKeys[0].toBase58()}`);
  tx.sign([wallet]);
  seal({ transaction: bs58.encode(tx.serialize()) });
} else if (mode === "message") {
  if (!link.pathname.endsWith("/signMessage")) throw new Error(`The last link is ${link.pathname}, not a signMessage`);
  const opened = nacl.box.open.after(bs58.decode(p.get("payload")), bs58.decode(p.get("nonce")), shared);
  if (!opened) throw new Error("The request didn't open: it was sealed for another Phantom key");
  const request = JSON.parse(Buffer.from(opened).toString());
  const message = bs58.decode(request.message);
  console.error(`signing the message ${JSON.stringify(Buffer.from(message).toString("utf8"))}`);
  seal({ signature: bs58.encode(nacl.sign.detached(message, wallet.secretKey)), publicKey: wallet.publicKey.toBase58() });
} else if (mode === "cancel") {
  reply.searchParams.set("errorCode", "4001");
  reply.searchParams.set("errorMessage", "User rejected the request.");
} else {
  throw new Error("connect, sign or cancel?");
}
execFileSync("xcrun", ["simctl", "openurl", SIM, reply.toString()]);
state.answered = p.get("nonce");
writeFileSync(STATE, JSON.stringify(state));
console.log(`answered ${mode}: ${reply.protocol}//${reply.host}${reply.pathname}`);
