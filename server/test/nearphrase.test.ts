import { describe, expect, it } from "vitest";
import { chainOfAddress, parseEarnPhrase, parseNearPhrase, parsePotPhrase } from "../src/lib/nearphrase.js";

/** docs/NEAR-SPEC.md's table of what people type, read the server's way. */

const BC1 = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";

describe("NEAR phrases", () => {
  it("reads swaps across chains, with each side's chain said or implied", () => {
    expect(parseNearPhrase("swap 20 usdc on base to sol")).toEqual({ kind: "swap",
      quote: { sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20", exact: "in" } });
    expect(parseNearPhrase("Swap 0.2 SOL to USDC on Base")?.quote).toEqual(
      { sell: "SOL", sellChain: "solana", buy: "USDC", buyChain: "base", amount: "0.2", exact: "in" });
    expect(parseNearPhrase("swap 20 usdc on base to near")?.quote).toMatchObject({ buy: "NEAR", buyChain: "near" });
    expect(parseNearPhrase("swap 20 usdc on base to zec")?.quote).toMatchObject({ buy: "ZEC", buyChain: "zcash" });
    expect(parseNearPhrase("swap 0.01 btc to usdc on base")?.quote).toMatchObject({ sell: "BTC", sellChain: "bitcoin", buyChain: "base" });
    expect(parseNearPhrase("swap .5 eth to sol")?.quote).toMatchObject({ sell: "ETH", sellChain: "base", amount: "0.5" });
  });

  it("keeps a typed recipient on a swap", () => {
    expect(parseNearPhrase(`swap 50 usdc on arbitrum to btc to ${BC1}`)).toEqual({ kind: "swap",
      quote: { sell: "USDC", sellChain: "arbitrum", buy: "BTC", buyChain: "bitcoin", amount: "50", exact: "in", recipient: BC1 } });
  });

  it("reads a move of the same coin between chains", () => {
    expect(parseNearPhrase("move 50 usdc from base to solana")).toEqual({ kind: "move",
      quote: { sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "solana", amount: "50", exact: "in" } });
    expect(parseNearPhrase("bridge 50 usdc from base to base")).toBeNull();
  });

  it("reads sends as what the recipient gets, paid from USDC on Base unless told", () => {
    expect(parseNearPhrase("send 5 usdc to alice.near")).toEqual({ kind: "send",
      quote: { sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "near", amount: "5", exact: "out", recipient: "alice.near" } });
    expect(parseNearPhrase(`send 0.001 btc to ${BC1}`)?.quote).toEqual(
      { sell: "USDC", sellChain: "base", buy: "BTC", buyChain: "bitcoin", amount: "0.001", exact: "out", recipient: BC1 });
    expect(parseNearPhrase("pay bob.near 10 usdc with sol")?.quote).toEqual(
      { sell: "SOL", sellChain: "solana", buy: "USDC", buyChain: "near", amount: "10", exact: "out", recipient: "bob.near" });
    expect(parseNearPhrase("send 5 usdc to alice.near from solana")?.quote).toMatchObject({ sell: "USDC", sellChain: "solana" });
    expect(parseNearPhrase("send 5 usdc to alice.near with eth")?.quote).toMatchObject({ sell: "ETH", sellChain: "base" });
    expect(parseNearPhrase("send 5 usdc to alice.near with usdc on arbitrum")?.quote).toMatchObject({ sell: "USDC", sellChain: "arbitrum" });
    expect(parseNearPhrase("send 1 near to alice.near with near")?.quote).toMatchObject({ sell: "NEAR", sellChain: "near" });
  });

  it("knows the chain an address belongs to", () => {
    expect(chainOfAddress("alice.near")?.key).toBe("near");
    expect(chainOfAddress("f".repeat(64))?.key).toBe("near");
    expect(chainOfAddress(BC1)?.key).toBe("bitcoin");
    expect(chainOfAddress("t1Hsc1LR8yKnbbe3twRp88p6vFfC5t7DLbs")?.key).toBe("zcash");
    expect(chainOfAddress("0x2527D02599Ba641c19FEa793cD0F167589a0f10D")?.key).toBe("base");
    expect(chainOfAddress("7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU")?.key).toBe("solana");
    expect(chainOfAddress("hello")).toBeNull();
  });

  it("leaves everything else alone", () => {
    expect(parseNearPhrase("hello there")).toBeNull();
    expect(parseNearPhrase("swap usdc to sol")).toBeNull();
    expect(parseNearPhrase("swap 20 usdc on moon to sol")).toBeNull();
    expect(parseNearPhrase("send 5 usdc")).toBeNull();
  });
});

describe("Earn phrases", () => {
  it("reads idle coins put to work", () => {
    const usdc50 = { kind: "earn", direction: "in", coin: "USDC", amount: "50" };
    for (const t of ["put $50 to work", "put 50 usdc to work", "Put my 50 USDC to work.", "earn on 50 usdc", "earn yield on $50",
      "park 50 usdc", "park $50 in earn", "start earning on 50 usdc"]) expect(parseEarnPhrase(t), t).toEqual(usdc50);
    expect(parseEarnPhrase("put 0.5 sol to work")).toEqual({ kind: "earn", direction: "in", coin: "SOL", amount: "0.5" });
    expect(parseEarnPhrase("stake .5 sol in a vault")).toEqual({ kind: "earn", direction: "in", coin: "SOL", amount: "0.5" });
    expect(parseEarnPhrase("put 50 usdc on solana to work")).toEqual({ ...usdc50, chain: "solana" });
    expect(parseEarnPhrase("park 50 usdc on base")).toEqual({ ...usdc50, chain: "base" });
  });

  it("reads taking it back out, all of it or an amount", () => {
    expect(parseEarnPhrase("take my usdc out of earn")).toEqual({ kind: "earn", direction: "out", coin: "USDC" });
    expect(parseEarnPhrase("take my sol out of earn")).toEqual({ kind: "earn", direction: "out", coin: "SOL" });
    expect(parseEarnPhrase("take 20 usdc out of earn")).toEqual({ kind: "earn", direction: "out", coin: "USDC", amount: "20" });
    expect(parseEarnPhrase("withdraw $20 from earn")).toEqual({ kind: "earn", direction: "out", coin: "USDC", amount: "20" });
    expect(parseEarnPhrase("take 20 usdc out of earn to solana")).toMatchObject({ direction: "out", chain: "solana" });
  });

  it("leaves everything else alone", () => {
    for (const t of ["earn on 50 doge", "take it out", "park the car", "put the kids to work", "put 50 usdc on moon to work",
      "swap 20 usdc on base to sol"]) expect(parseEarnPhrase(t), t).toBeNull();
  });
});

describe("pot phrases", () => {
  it("reads a look at the pot", () => {
    expect(parsePotPhrase("how much is in the trip pot")).toEqual({ kind: "pot", ask: "balance", pot: "trip" });
    expect(parsePotPhrase("How much is left in the trip pot?")).toEqual({ kind: "pot", ask: "balance", pot: "trip" });
    expect(parsePotPhrase("what's in the pot")).toEqual({ kind: "pot", ask: "balance" });
    expect(parsePotPhrase("check the trip pot")).toEqual({ kind: "pot", ask: "balance", pot: "trip" });
    expect(parsePotPhrase("pot balance")).toEqual({ kind: "pot", ask: "balance" });
    expect(parsePotPhrase("how much is in build.sputnik-dao.near")).toEqual({ kind: "pot", ask: "balance", dao: "build.sputnik-dao.near" });
  });

  it("reads a payout from the pot, to a name or a NEAR account", () => {
    expect(parsePotPhrase("pay the caterer $120 from the pot")).toEqual({ kind: "pot", ask: "pay", payee: "the caterer", amount: "120", coin: "USDC" });
    expect(parsePotPhrase("pay caterer.near 120 usdc from the trip pot for catering")).toEqual({ kind: "pot", ask: "pay",
      payee: "caterer.near", amount: "120", coin: "USDC", pot: "trip", note: "catering" });
    expect(parsePotPhrase("send bob.near 5 near out of the pot")).toEqual({ kind: "pot", ask: "pay", payee: "bob.near", amount: "5", coin: "NEAR" });
  });

  it("leaves everything else alone", () => {
    for (const t of ["pay the caterer $120", "how much is in the bank", "the pot is boiling", "send 5 usdc to alice.near"]) {
      expect(parsePotPhrase(t), t).toBeNull();
    }
  });
});
