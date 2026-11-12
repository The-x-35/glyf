import { describe, expect, it } from "vitest";
import { chainOfAddress, parseNearPhrase } from "../src/lib/nearphrase.js";

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
