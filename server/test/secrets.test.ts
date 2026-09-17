import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { SecretVault, luhn, verhoeff } from "../src/lib/secrets.js";
import { completeStreaming, lastOutboundForTests } from "../src/providers/openrouter.js";

const masked = (text: string) => {
  const v = new SecretVault();
  return { out: v.mask(text), vault: v };
};

describe("check digits", () => {
  it("knows a real card number from a typo", () => {
    expect(luhn("4111111111111111")).toBe(true);
    expect(luhn("4111111111111112")).toBe(false);
  });

  it("knows a real Aadhaar number from a typo", () => {
    expect(verhoeff("234123412346")).toBe(true);
    expect(verhoeff("234123412347")).toBe(false);
  });
});

describe("SecretVault.mask", () => {
  it("hides a card number however it is grouped, and its CVV", () => {
    const { out } = masked("my card is 4111 1111 1111 1111 exp 12/29 cvv 123 pls pay");
    expect(out).toBe("my card is [[S1]] exp 12/29 cvv [[S2]] pls pay");
    expect(masked("4111-1111-1111-1111").out).toBe("[[S1]]");
    expect(masked("card 5555555555554444 ok").out).toBe("card [[S1]] ok");
  });

  it("leaves ordinary numbers alone", () => {
    for (const text of [
      "call me on +91 98765 43210", "the total is 12,450 for 3 nights", "flight AI 2021 at 6:40",
      "order 4111111111111112 shipped", "meet at 42 Glass Lane 560038", "see you at 5",
    ]) {
      expect(masked(text).out).toBe(text);
    }
  });

  it("hides one-time codes, PINs and passwords but keeps what they are", () => {
    expect(masked("otp is 482913 dont share").out).toBe("otp is [[S1]] dont share");
    expect(masked("my upi pin: 4821").out).toBe("my upi pin: [[S1]]");
    expect(masked("wifi password is Sunny@2024!").out).toBe("wifi password is [[S1]]");
    expect(masked("the password was changed").out).toBe("the password was changed");
  });

  it("hides government ids", () => {
    expect(masked("aadhaar 2341 2341 2346").out).toBe("aadhaar [[S1]]");
    expect(masked("PAN is ABCDE1234F").out).toBe("PAN is [[S1]]");
    expect(masked("ssn 123-45-6789").out).toBe("ssn [[S1]]");
    expect(masked("IBAN GB82 WEST 1234 5698 7654 32").out).toBe("IBAN [[S1]]");
  });

  it("hides keys and recovery phrases", () => {
    expect(masked("key sk-proj-abcdefghijklmnopqrstuvwxyz012345").out).toBe("key [[S1]]");
    const phrase = "seed phrase: abandon ability able about above absent absorb abstract absurd abuse access accident";
    expect(masked(phrase).out).toBe("seed phrase: [[S1]]");
    const base58 = "5".repeat(1) + "K".repeat(40) + "h".repeat(40);
    expect(masked(`private key ${base58}`).out).toBe("private key [[S1]]");
  });

  it("gives the same value the same placeholder", () => {
    expect(masked("4111111111111111 or 4111111111111111").out).toBe("[[S1]] or [[S1]]");
  });
});

describe("SecretVault.restore", () => {
  it("puts values back, in prose and inside JSON", () => {
    const { out, vault } = masked('wifi password is a"b\\c');
    expect(out).toBe("wifi password is [[S1]]");
    expect(vault.restore("The password is [[S1]].")).toBe('The password is a"b\\c.');
    const json = vault.restore('{"basic":"Password: [[S1]]"}');
    expect(JSON.parse(json).basic).toBe('Password: a"b\\c');
  });

  it("restores a placeholder split across streamed tokens", () => {
    const { vault } = masked("card 4111111111111111");
    const out: string[] = [];
    const s = vault.restoringStream(t => out.push(t));
    for (const t of ["Card: [", "[S", "1", "]", "] thanks [x]"]) s.push(t);
    s.flush();
    expect(out.join("")).toBe("Card: 4111111111111111 thanks [x]");
  });
});

describe("completeStreaming", () => {
  beforeAll(() => {
    env.mockAI = true; // no quota spent, and the outbound messages are still captured
  });

  it("never sends a secret to the model and gives it back in the reply", async () => {
    const tokens: string[] = [];
    const res = await completeStreaming("fast",
      [{ role: "user", content: "[[act.rewrite]]\nmy card is 4111 1111 1111 1111 cvv 123" }],
      { onToken: t => tokens.push(t) });
    const sent = JSON.stringify(lastOutboundForTests);
    expect(sent).not.toContain("4111");
    expect(sent).not.toContain("cvv 123");
    expect(sent).toContain("[[S1]]");
    expect(res.text).not.toContain("[[S");
  });
});
