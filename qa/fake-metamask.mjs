#!/usr/bin/env node
// Stands in for MetaMask on the simulator (there is no MetaMask there).
// The app, launched with --glyf-test-metamask, writes the deeplink it would
// have opened into Documents/metamask-request.txt; this reads it, answers the
// way MetaMask Mobile does (DeeplinkProtocolService.ts: base64 JSON on
// glyf://mmsdk?message=…), signing with Hardhat's well-known test key #0.
//
//   node qa/fake-metamask.mjs <path to metamask-request.txt> [--hash 0x…] [--refuse]
//
// --hash answers eth_sendTransaction with that hash (nothing is sent: use a
// real Base transaction to see the app refuse one that isn't its own).
// --account 1 signs as Hardhat's test account #1 (0x7099…79C8) instead of
// #0: NEAR Intents' 1Click refuses a live quote refunding to #0 (0xf39F…2266,
// a key everyone knows) with "Failed to get quote", so NEAR trades need #1.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(new URL("../server/package.json", import.meta.url));
const { privateKeyToAccount } = require("viem/accounts");

const args = process.argv.slice(2);
const keys = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
];
const account = privateKeyToAccount(keys[args.includes("--account") ? Number(args[args.indexOf("--account") + 1]) : 0]);
const file = args[0];
const hash = args.includes("--hash") ? args[args.indexOf("--hash") + 1] : null;
const refuse = args.includes("--refuse");

const url = new URL(readFileSync(file, "utf8").trim());
let id;
let rpcs;
if (url.host === "connect") {
  const req = JSON.parse(url.searchParams.get("request"));
  id = req.id;
  rpcs = [{ method: "personal_sign", params: [req.params[0], account.address] }];
} else {
  const msg = JSON.parse(Buffer.from(url.searchParams.get("message"), "base64").toString("utf8"));
  id = msg.id;
  rpcs = msg.method === "metamask_batch" ? msg.params : [msg];
}

async function answer(rpc) {
  switch (rpc.method) {
    case "wallet_switchEthereumChain": return null;
    case "personal_sign": return account.signMessage({ message: { raw: rpc.params[0] } });
    case "eth_signTypedData_v4": {
      const t = JSON.parse(rpc.params[1]);
      const { EIP712Domain, ...types } = t.types;
      return account.signTypedData({ domain: t.domain, types, primaryType: t.primaryType, message: t.message });
    }
    case "eth_sendTransaction":
      if (!hash) throw new Error("pass --hash 0x… to answer a transaction");
      return hash;
    default: throw new Error(`no stand-in for ${rpc.method}`);
  }
}

const results = [];
if (!refuse) for (const rpc of rpcs) results.push(await answer(rpc));
const data = refuse
  ? { id, error: { code: 4001, message: "User rejected the request." } }
  : { id, result: rpcs.length === 1 ? results[0] : results };
const reply = { data: { ...data, jsonrpc: "2.0", accounts: [account.address], chainId: "0x2105" }, name: "metamask-provider" };
const link = `glyf://mmsdk?message=${encodeURIComponent(Buffer.from(JSON.stringify(reply)).toString("base64"))}`;
console.log(`${url.host} ${rpcs.map(r => r.method).join(",")} → ${refuse ? "refused" : "answered"} as ${account.address}`);
execFileSync("xcrun", ["simctl", "openurl", process.env.SIM_UDID ?? "04652CB6-3351-4F5E-934D-EF7A0B7F8585", link]);
