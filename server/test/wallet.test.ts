import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { walletRoutes } from "../src/routes/wallet.js";

describe("POST /wallet/rpc", () => {
  function setup(answer: unknown, rpcUrl: string | undefined = "https://rpc.example/?api-key=secret") {
    const calls: { url: string; body: unknown }[] = [];
    const app = Fastify();
    walletRoutes(app, {
      rpcUrl,
      fetchImpl: (async (url: string, init: RequestInit) => {
        calls.push({ url, body: JSON.parse(String(init.body)) });
        return new Response(JSON.stringify(answer), { headers: { "content-type": "application/json" } });
      }) as unknown as typeof fetch,
    });
    const rpc = (method: string, params: unknown[] = []) =>
      app.inject({ method: "POST", url: "/wallet/rpc", payload: { method, params } });
    return { app, calls, rpc };
  }

  it("carries a wallet call to the node, key and all, and hands back the result", async () => {
    const { calls, rpc } = setup({ jsonrpc: "2.0", id: 1, result: { value: 1_000_000 } });
    const res = await rpc("getBalance", ["7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"]);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, result: { value: 1_000_000 } });
    expect(calls[0].url).toContain("api-key=secret");
    expect(calls[0].body).toMatchObject({ jsonrpc: "2.0", method: "getBalance" });
    // The key is never in anything sent back to the phone.
    expect(res.body).not.toContain("secret");
  });

  it("refuses anything a wallet doesn't need", async () => {
    const { calls, rpc } = setup({ result: null });
    for (const method of ["getProgramAccounts", "requestAirdrop", "getBlock"]) {
      expect((await rpc(method)).statusCode).toBe(400);
    }
    expect(calls).toHaveLength(0);
  });

  it("passes on the node's own error", async () => {
    const { rpc } = setup({ jsonrpc: "2.0", id: 1, error: { code: -32002, message: "Transaction simulation failed: insufficient funds" } });
    const res = await rpc("sendTransaction", ["AQ==", { encoding: "base64" }]);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toMatch(/insufficient funds/);
  });

  it("says so when no RPC is set up", async () => {
    const { rpc } = setup({ result: null }, "");
    expect((await rpc("getLatestBlockhash")).statusCode).toBe(503);
  });
});

describe("GET /wallet/fees", () => {
  async function fees(env: Record<string, string | undefined>) {
    const saved = { ...process.env };
    Object.assign(process.env, { GLYF_FEE_WALLET: undefined, GLYF_TREASURY: undefined, GLYF_PRIVATE_FEE_BPS: undefined });
    for (const [k, v] of Object.entries(env)) {
      if (v === undefined) delete process.env[k]; else process.env[k] = v;
    }
    for (const k of ["GLYF_FEE_WALLET", "GLYF_TREASURY", "GLYF_PRIVATE_FEE_BPS"]) if (!(k in env)) delete process.env[k];
    try {
      const app = Fastify();
      walletRoutes(app, {});
      return (await app.inject({ method: "GET", url: "/wallet/fees" })).json();
    } finally {
      process.env = saved;
    }
  }
  const wallet = "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1";

  it("is 0.1% to the fee wallet when one is set", async () => {
    expect(await fees({ GLYF_FEE_WALLET: wallet })).toEqual({ ok: true, privateFeeBps: 10, feeWallet: wallet });
  });
  it("falls back to the treasury", async () => {
    expect((await fees({ GLYF_TREASURY: wallet })).feeWallet).toBe(wallet);
  });
  it("is off with no wallet or a bad one", async () => {
    expect(await fees({})).toEqual({ ok: true, privateFeeBps: 0, feeWallet: null });
    expect((await fees({ GLYF_FEE_WALLET: "not-an-address" })).privateFeeBps).toBe(0);
  });
  it("takes a rate, never above 1%", async () => {
    expect((await fees({ GLYF_FEE_WALLET: wallet, GLYF_PRIVATE_FEE_BPS: "20" })).privateFeeBps).toBe(20);
    expect((await fees({ GLYF_FEE_WALLET: wallet, GLYF_PRIVATE_FEE_BPS: "500" })).privateFeeBps).toBe(10);
  });
});
