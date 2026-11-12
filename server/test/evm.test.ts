import Fastify from "fastify";
import { decodeFunctionData, encodeFunctionResult, getAddress } from "viem";
import { describe, expect, it } from "vitest";
import { chainOf, EVM_CHAINS } from "../src/lib/evm.js";
import { ERC20_ABI, findSolanaToken, findToken, NATIVE, tokensOn, wrappedNative } from "../src/lib/tokens.js";
import { evmRoutes } from "../src/routes/evm.js";

type Rpc = { url: string; method: string; params: unknown[] };

/** A stand-in node: answers each JSON-RPC call with `answer`, records it. */
function fakeNode(answer: (call: Rpc) => unknown) {
  const calls: Rpc[] = [];
  const fetchImpl = (async (url: string, init: RequestInit) => {
    const { method, params } = JSON.parse(String(init.body));
    const call = { url: String(url), method, params };
    calls.push(call);
    const body = answer(call);
    if (body instanceof Error) throw body;
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, ...(body as object) }),
      { headers: { "content-type": "application/json" } });
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

describe("chains and tokens", () => {
  it("knows a chain by key, nickname or id", () => {
    expect(chainOf("base")?.id).toBe(8453);
    expect(chainOf("Arb")?.key).toBe("arbitrum");
    expect(chainOf("op")?.key).toBe("optimism");
    expect(chainOf(130)?.key).toBe("unichain");
    expect(chainOf("1874")).toBeNull();
    expect(chainOf("base sepolia")?.id).toBe(84532);
    expect(chainOf("polygon")).toBeNull();
  });

  it("turns what people type into the listed coin", () => {
    const base = EVM_CHAINS.base;
    expect(findToken(base, "eth")).toMatchObject({ symbol: "ETH", address: NATIVE, native: true, decimals: 18 });
    expect(findToken(base, "$USDC")?.address).toBe("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
    // Base has no WBTC listed: bitcoin there is cbBTC.
    expect(findToken(base, "btc")?.symbol).toBe("cbBTC");
    expect(findToken(EVM_CHAINS.ethereum, "btc")?.symbol).toBe("WBTC");
    expect(findToken(base, "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913")?.symbol).toBe("USDC");
    expect(findToken(base, "USDT")).toBeNull();
    expect(wrappedNative(EVM_CHAINS.sepolia)?.symbol).toBe("WETH");
    expect(findToken(EVM_CHAINS.optimism, "usdt")?.address)
      .toBe(getAddress("0x94b008aA00579c1307B0EF2c499aD98a8ce58e58"));
    expect(tokensOn(EVM_CHAINS.unichain)[0].symbol).toBe("ETH");
    expect(findSolanaToken("sol")?.address).toBe("So11111111111111111111111111111111111111112");
  });
});

describe("POST /evm/rpc", () => {
  function setup(answer: (call: Rpc) => unknown) {
    const node = fakeNode(answer);
    const app = Fastify();
    evmRoutes(app, { fetchImpl: node.fetchImpl });
    const rpc = (chain: unknown, method: string, params: unknown[] = []) =>
      app.inject({ method: "POST", url: "/evm/rpc", payload: { chain, method, params } });
    return { ...node, rpc };
  }

  it("carries a wallet call to the chain's node and hands back the result", async () => {
    const { calls, rpc } = setup(() => ({ result: "0x2105" }));
    const res = await rpc("base", "eth_chainId");
    expect(res.json()).toEqual({ ok: true, result: "0x2105" });
    expect(calls[0]).toMatchObject({ url: "https://base-rpc.publicnode.com", method: "eth_chainId" });
    await rpc(84532, "eth_blockNumber");
    expect(calls[1].url).toBe("https://base-sepolia-rpc.publicnode.com");
  });

  it("uses a chain's own variable when set", async () => {
    const saved = process.env.ARBITRUM_RPC_URL;
    process.env.ARBITRUM_RPC_URL = "https://arb.example/key";
    try {
      const { calls, rpc } = setup(() => ({ result: "0x1" }));
      await rpc("arbitrum", "eth_blockNumber");
      expect(calls[0].url).toBe("https://arb.example/key");
    } finally {
      if (saved === undefined) delete process.env.ARBITRUM_RPC_URL; else process.env.ARBITRUM_RPC_URL = saved;
    }
  });

  it("refuses methods a wallet doesn't need, and unknown chains", async () => {
    const { calls, rpc } = setup(() => ({ result: null }));
    for (const method of ["eth_sign", "eth_sendTransaction", "debug_traceTransaction", "eth_accounts"]) {
      expect((await rpc("base", method)).statusCode).toBe(400);
    }
    expect((await rpc("solana", "eth_chainId")).statusCode).toBe(400);
    expect(calls).toHaveLength(0);
  });

  it("passes on the node's own error, and says when the node is down", async () => {
    const { rpc } = setup(call => call.method === "eth_sendRawTransaction"
      ? { error: { code: -32000, message: "insufficient funds for gas * price + value" } }
      : new Error("connect ECONNREFUSED"));
    const sent = await rpc("base", "eth_sendRawTransaction", ["0x02f8"]);
    expect(sent.statusCode).toBe(400);
    expect(sent.json()).toMatchObject({ ok: false, code: -32000, error: /insufficient funds/ });
    const down = await rpc("optimism", "eth_blockNumber");
    expect(down.statusCode).toBe(502);
    expect(down.json().error).toMatch(/OP Mainnet/);
  });
});

describe("GET /evm/tokens and /evm/balances", () => {
  const owner = "0x1111111111111111111111111111111111111111";

  it("lists a chain's coins, gas coin first", async () => {
    const app = Fastify();
    evmRoutes(app, { fetchImpl: fakeNode(() => ({})).fetchImpl });
    const res = await app.inject({ method: "GET", url: "/evm/tokens?chain=base" });
    const body = res.json();
    expect(body.chain).toMatchObject({ key: "base", id: 8453, native: "ETH" });
    expect(body.tokens[0]).toMatchObject({ symbol: "ETH", decimals: 18, native: true });
    expect(body.tokens.map((x: { symbol: string }) => x.symbol)).toEqual(["ETH", "WETH", "USDC", "DAI", "cbBTC", "LINK"]);
    expect((await app.inject({ method: "GET", url: "/evm/tokens?chain=nowhere" })).statusCode).toBe(400);
  });

  it("reads the gas coin and every listed token, as base units and decimals", async () => {
    const usdc = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
    const { fetchImpl, calls } = fakeNode(call => {
      if (call.method === "eth_getBalance") return { result: "0x" + (15n * 10n ** 16n).toString(16) };
      const { to, data } = call.params[0] as { to: string; data: `0x${string}` };
      const { args } = decodeFunctionData({ abi: ERC20_ABI, data });
      expect(args?.[0]).toBe(getAddress(owner));
      if (getAddress(to) === usdc) return { result: encodeFunctionResult({ abi: ERC20_ABI, functionName: "balanceOf", result: 20_500_000n }) };
      if (to.toLowerCase().startsWith("0x50c5")) return { error: { code: -32000, message: "execution reverted" } };
      return { result: encodeFunctionResult({ abi: ERC20_ABI, functionName: "balanceOf", result: 0n }) };
    });
    const app = Fastify();
    evmRoutes(app, { fetchImpl });
    const res = await app.inject({ method: "GET", url: `/evm/balances?chain=base&address=${owner}` });
    expect(res.statusCode).toBe(200);
    const { balances } = res.json() as { balances: { symbol: string; amount: string; raw: string }[] };
    expect(balances.find(b => b.symbol === "ETH")).toMatchObject({ amount: "0.15", raw: "150000000000000000" });
    expect(balances.find(b => b.symbol === "USDC")).toMatchObject({ amount: "20.5", raw: "20500000", decimals: 6 });
    // DAI's call failed: left out, not shown as zero.
    expect(balances.some(b => b.symbol === "DAI")).toBe(false);
    expect(calls).toHaveLength(6);
    expect((await app.inject({ method: "GET", url: "/evm/balances?chain=base&address=nope" })).statusCode).toBe(400);
  });
});
