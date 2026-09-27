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
