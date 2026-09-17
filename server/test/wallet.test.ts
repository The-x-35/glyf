import { describe, expect, it } from "vitest";
import { baseUnits, MINTS } from "../src/lib/magicblock.js";

describe("magicblock amounts", () => {
  it("converts whole tokens to base units without floating point", () => {
    expect(baseUnits("1", 6)).toBe(1_000_000n);
    expect(baseUnits("12.5", 6)).toBe(12_500_000n);
    expect(baseUnits("0.000001", 6)).toBe(1n);
    // More precision than the mint has is truncated, never rounded up.
    expect(baseUnits("1.2345678", 6)).toBe(1_234_567n);
    // A price typed with a separator still works.
    expect(baseUnits("1,000", 6)).toBe(1_000_000_000n);
  });

  it("refuses anything that is not a positive number", () => {
    for (const bad of ["", ".", "abc", "-5", "1.2.3", "0", "0.0"]) {
      expect(() => baseUnits(bad, 6)).toThrow();
    }
  });

  it("knows the stablecoin mints the wallet offers", () => {
    expect(MINTS.USDC.mint).toBe("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v");
    expect(MINTS.USDC.decimals).toBe(6);
  });
});
