import { describe, expect, it } from "vitest";
import type { NearLookup } from "../src/lib/names.js";
import { guardRecipient, shortAddress } from "../src/lib/nearguard.js";
import { NEAR_CHAINS } from "../src/lib/nearintents.js";

/** Guard, check by check (docs/NEAR-SPEC.md, "Guard"). */

const PAID = "0xAb12000000000000000000000000000000009fE0";
const TWIN = "0xAB12ffffffffffffffffffffffffffffffff9FE0";
const PHANTOM = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU";
const near = (accounts: string[], fail = false): NearLookup & { asked: string[] } => {
  const asked: string[] = [];
  return { asked, exists: async a => { asked.push(a); if (fail) throw new Error("down"); return accounts.includes(a); } };
};
const ids = (a: { checks: { id: string; level: string }[] }) => a.checks.map(c => `${c.level}:${c.id}`);

describe("Guard", () => {
  it("passes a recipient paid before, on the right chain, under every limit", async () => {
    const a = await guardRecipient({ recipient: PAID.toLowerCase(), chain: NEAR_CHAINS.base, recent: [PAID], amountInUsd: 20,
      dailyLimitUsd: 200, spentTodayUsd: 40 }, near([]));
    expect(a).toEqual({ level: "ok", checks: [] });
  });

  it("blocks an address that shares a past one's first and last four but isn't it", async () => {
    const a = await guardRecipient({ recipient: TWIN, chain: NEAR_CHAINS.base, recent: [PAID], amountInUsd: 20 }, near([]));
    expect(a.level).toBe("block");
    expect(a.checks[0]).toEqual({ id: "lookalike", level: "block", text: "Looks like 0xAb12…9fE0 you paid before, but it isn't" });
    expect(ids(a)).toEqual(["block:lookalike", "warn:new-recipient"]);
    // Base58 keeps its case: a twin must match it exactly at both ends.
    const sol = await guardRecipient({ recipient: "7xKXzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzgAsU", chain: NEAR_CHAINS.solana,
      recent: [PHANTOM] }, near([]));
    expect(sol.checks[0]).toMatchObject({ id: "lookalike", text: "Looks like 7xKX…gAsU you paid before, but it isn't" });
    const notTwin = await guardRecipient({ recipient: "7XKXzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzgAsU", chain: NEAR_CHAINS.solana,
      recent: [PHANTOM] }, near([]));
    expect(ids(notTwin)).toEqual(["warn:new-recipient"]);
  });

  it("blocks a .near name NEAR doesn't have, and only warns when NEAR can't be asked", async () => {
    const lookup = near(["alice.near"]);
    expect(ids(await guardRecipient({ recipient: "alice.near", chain: NEAR_CHAINS.near, recent: ["alice.near"] }, lookup))).toEqual([]);
    const missing = await guardRecipient({ recipient: "bob.near", chain: NEAR_CHAINS.near }, lookup);
    expect(missing.checks[0]).toEqual({ id: "no-account", level: "block", text: "No NEAR account bob.near" });
    // An implicit account is never looked up: it is paid into being.
    await guardRecipient({ recipient: "a".repeat(64), chain: NEAR_CHAINS.near }, lookup);
    expect(lookup.asked).toEqual(["alice.near", "bob.near"]);
    const down = await guardRecipient({ recipient: "bob.near", chain: NEAR_CHAINS.near, recent: ["bob.near"] }, near([], true));
    expect(down).toEqual({ level: "warn", checks: [{ id: "no-account", level: "warn", text: "Couldn't check bob.near on NEAR" }] });
  });

  it("blocks an address that can't be on the destination chain", async () => {
    const evmForSol = await guardRecipient({ recipient: PAID, chain: NEAR_CHAINS.solana, recent: [PAID] }, near([]));
    expect(evmForSol.checks).toEqual([{ id: "chain-mismatch", level: "block", text: "That's an EVM address, not Solana" }]);
    const solForBtc = await guardRecipient({ recipient: PHANTOM, chain: NEAR_CHAINS.bitcoin, recent: [PHANTOM] }, near([]));
    expect(solForBtc.checks[0].text).toBe("That's a Solana address, not Bitcoin");
    const junk = await guardRecipient({ recipient: "hello world", chain: NEAR_CHAINS.zcash, recent: ["hello world"] }, near([]));
    expect(junk.checks[0].text).toBe("That isn't a Zcash address");
  });

  it("warns a first payment, a day over the person's own limit, and anything over $1,000", async () => {
    const a = await guardRecipient({ recipient: PAID, chain: NEAR_CHAINS.base, recent: [], amountInUsd: 1200.5,
      dailyLimitUsd: 200, spentTodayUsd: 40 }, near([]));
    expect(a).toEqual({ level: "warn", checks: [
      { id: "new-recipient", level: "warn", text: "First time paying this address" },
      { id: "over-limit", level: "warn", text: "Over your $200 a day ($40 spent today)" },
      { id: "big", level: "warn", text: "Over $1,000" },
    ] });
    // No limit set, no price known: nothing to say about either.
    expect(ids(await guardRecipient({ recipient: PAID, chain: NEAR_CHAINS.base, recent: [PAID], amountInUsd: null }, near([])))).toEqual([]);
    expect(ids(await guardRecipient({ recipient: PAID, chain: NEAR_CHAINS.base, recent: [PAID], amountInUsd: 170,
      dailyLimitUsd: 200, spentTodayUsd: 40 }, near([])))).toEqual(["warn:over-limit"]);
  });

  it("shortens addresses enough to recognise them", () => {
    expect(shortAddress(PAID)).toBe("0xAb12…9fE0");
    expect(shortAddress(PHANTOM)).toBe("7xKX…gAsU");
    expect(shortAddress("alice.near")).toBe("alice.near");
  });
});
