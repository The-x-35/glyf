import Fastify from "fastify";
import { decodeFunctionData, encodeAbiParameters, encodeFunctionResult, getAddress, parseAbi, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { base58, COIN_TYPES, ensName, NEAR_RPC, nearRpc, resolveEns, viemEns, type EnsLookup, type NearLookup, type SnsLookup } from "../src/lib/names.js";
import { namesRoutes } from "../src/routes/names.js";

const ARPIT = getAddress("0x1234567890abcdef1234567890abcdef12345678");
const BASE_ONLY = getAddress("0xabcdef0123456789abcdef0123456789abcdef01");
const SOL_BYTES = ("0x" + "11".repeat(32)) as Hex;

/** A stand-in for ENS: records per name and coin type, as viem hands them. */
function fakeEns(records: Record<string, Record<number, Hex>>, primary: Record<string, string> = {}) {
  const asked: { name: string; coinType: number }[] = [];
  const ens: EnsLookup = {
    async address(name, coinType) {
      asked.push({ name, coinType });
      return records[name]?.[coinType] ?? null;
    },
    async text(name, key) {
      return key === "avatar" && records[name] ? "https://example.com/arpit.png" : null;
    },
    async name(address) {
      return primary[address] ?? null;
    },
  };
  return { ens, asked };
}

function fakeSns(names: Record<string, string>, primary: Record<string, string> = {}): SnsLookup {
  return {
    async resolve(name) { return names[name] ?? null; },
    async primary(owner) { return primary[owner] ?? null; },
  };
}

describe("names", () => {
  it("asks every chain by its ENSIP-11 coin type", () => {
    expect(COIN_TYPES.base).toBe(2147492101);
    expect(COIN_TYPES.arbitrum).toBe(2147525809);
    expect(COIN_TYPES.optimism).toBe(2147483658);
    expect(COIN_TYPES.polygon).toBe(2147483785);
  });

  it("reads Solana's 32 raw bytes as a base58 address", () => {
    expect(base58(new Uint8Array(32))).toBe("11111111111111111111111111111111");
    expect(base58(Uint8Array.from([0, 0, 1]))).toBe("112");
    expect(base58(Uint8Array.from(Buffer.from("hello world")))).toBe("StV1DL6CwTryKyV");
  });

  it("normalises names and refuses what ENS can't", () => {
    expect(ensName("Arpit.ETH")).toBe("arpit.eth");
    expect(ensName("pay.arpit.glyfapp.eth")).toBe("pay.arpit.glyfapp.eth");
    expect(ensName("arpit")).toBeNull();
    expect(ensName("bad\u0000name.eth")).toBeNull();
  });

  it("fills an L2 from its own record, then the default, then Ethereum's (and says which were inferred)", async () => {
    const { ens } = fakeEns({ "arpit.eth": {
      [COIN_TYPES.ethereum]: ARPIT.toLowerCase() as Hex,
      [COIN_TYPES.base]: BASE_ONLY.toLowerCase() as Hex,
      [COIN_TYPES.solana]: SOL_BYTES,
    } });
    const answer = await resolveEns(ens, "arpit.eth");
    expect(answer?.addresses).toEqual({
      ethereum: ARPIT, base: BASE_ONLY, arbitrum: ARPIT, optimism: ARPIT, polygon: ARPIT,
      solana: base58(new Uint8Array(32).fill(0x11)),
    });
    expect(answer?.inferred).toEqual(["arbitrum", "optimism", "polygon"]);
    expect(answer?.avatar).toBe("https://example.com/arpit.png");
  });

  it("is null for a name with no addresses", async () => {
    const { ens } = fakeEns({});
    expect(await resolveEns(ens, "nobody.eth")).toBeNull();
  });

  it("asks the Universal Resolver on mainnet through the configured RPC", async () => {
    const UR = parseAbi(["function resolveWithGateways(bytes name, bytes data, string[] gateways) view returns (bytes, address)"]);
    const RESOLVER = parseAbi([
      "function addr(bytes32 node, uint256 coinType) view returns (bytes)",
      "function text(bytes32 node, string key) view returns (string)",
    ]);
    const urls: string[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      urls.push(String(url));
      const { id, params } = JSON.parse(String(init.body));
      const { args } = decodeFunctionData({ abi: UR, data: params[0].data });
      const inner = decodeFunctionData({ abi: RESOLVER, data: args[1] as Hex });
      let result: Hex = "0x";
      if (inner.functionName === "addr" && inner.args[1] === 60n) {
        result = encodeFunctionResult({ abi: RESOLVER, functionName: "addr", result: ARPIT.toLowerCase() as Hex });
      }
      const encoded = encodeAbiParameters([{ type: "bytes" }, { type: "address" }],
        [result, "0x0000000000000000000000000000000000000001"]);
      return new Response(JSON.stringify({ jsonrpc: "2.0", id, result: encoded }), { headers: { "content-type": "application/json" } });
    }) as unknown as typeof fetch;
    const saved = process.env.ETH_RPC_URL;
    process.env.ETH_RPC_URL = "https://eth.example/rpc";
    try {
      const answer = await resolveEns(viemEns(fetchImpl), "arpit.eth");
      expect(answer?.addresses.ethereum).toBe(ARPIT);
      expect(answer?.addresses.base).toBe(ARPIT);
      expect(answer?.inferred).toContain("base");
      expect(urls.every(u => u === "https://eth.example/rpc")).toBe(true);
    } finally {
      if (saved === undefined) delete process.env.ETH_RPC_URL; else process.env.ETH_RPC_URL = saved;
    }
  });
});

describe("GET /names/resolve and /names/reverse", () => {
  function setup(sns: SnsLookup | null = fakeSns({ "arpit.sol": "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj" },
    { "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj": "arpit.sol" })) {
    const { ens, asked } = fakeEns({ "arpit.eth": { [COIN_TYPES.ethereum]: ARPIT.toLowerCase() as Hex } }, { [ARPIT]: "arpit.eth" });
    const app = Fastify();
    namesRoutes(app, { ens, sns });
    return { app, asked };
  }

  it("resolves an ENS name to every chain's address", async () => {
    const { app } = setup();
    const res = await app.inject({ method: "GET", url: "/names/resolve?name=Arpit.eth" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true, found: true, name: "arpit.eth",
      addresses: { ethereum: ARPIT, base: ARPIT, arbitrum: ARPIT, optimism: ARPIT, polygon: ARPIT } });
  });

  it("resolves a .sol name through SNS", async () => {
    const { app, asked } = setup();
    const res = await app.inject({ method: "GET", url: "/names/resolve?name=arpit.sol" });
    expect(res.json()).toEqual({ ok: true, found: true, name: "arpit.sol",
      addresses: { solana: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj" } });
    expect(asked).toHaveLength(0);
  });

  it("says found:false with a 404 when nothing is there, and remembers it", async () => {
    const { app, asked } = setup();
    for (let i = 0; i < 2; i++) {
      const res = await app.inject({ method: "GET", url: "/names/resolve?name=nobody.eth" });
      expect(res.statusCode).toBe(404);
      expect(res.json()).toMatchObject({ found: false, name: "nobody.eth" });
    }
    expect(asked.filter(a => a.coinType === 60)).toHaveLength(1);
  });

  it("refuses a bare word, and .sol without a Solana RPC", async () => {
    const { app } = setup(null);
    expect((await app.inject({ method: "GET", url: "/names/resolve?name=arpit" })).statusCode).toBe(400);
    expect((await app.inject({ method: "GET", url: "/names/resolve?name=arpit.sol" })).statusCode).toBe(503);
  });

  it("is a 502 when the node doesn't answer, not 'no such name'", async () => {
    const app = Fastify();
    namesRoutes(app, { ens: { address: async () => { throw new Error("fetch failed"); },
      text: async () => null, name: async () => null }, sns: null });
    expect((await app.inject({ method: "GET", url: "/names/resolve?name=arpit.eth" })).statusCode).toBe(502);
  });

  it("names an address: ENS primary for 0x, SNS favourite for base58", async () => {
    const { app } = setup();
    const evm = await app.inject({ method: "GET", url: `/names/reverse?address=${ARPIT.toLowerCase()}` });
    expect(evm.json()).toEqual({ ok: true, found: true, address: ARPIT, name: "arpit.eth" });
    const sol = await app.inject({ method: "GET", url: "/names/reverse?address=7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj" });
    expect(sol.json().name).toBe("arpit.sol");
    const none = await app.inject({ method: "GET", url: `/names/reverse?address=${BASE_ONLY}` });
    expect(none.statusCode).toBe(404);
    expect((await app.inject({ method: "GET", url: "/names/reverse?address=hello" })).statusCode).toBe(400);
  });
});

describe(".near names", () => {
  const IMPLICIT = "98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbd6de";

  /** NEAR's view_account: accounts it has, UNKNOWN_ACCOUNT for the rest. */
  function fakeNear(accounts: string[], fail = false) {
    const asked: string[] = [];
    const near: NearLookup = {
      async exists(account) {
        asked.push(account);
        if (fail) throw new Error("fetch failed");
        return accounts.includes(account);
      },
    };
    const app = Fastify();
    namesRoutes(app, { ens: fakeEns({}).ens, sns: null, near });
    return { app, asked };
  }

  it("asks NEAR RPC view_account and reads UNKNOWN_ACCOUNT as no account", async () => {
    const bodies: { url: string; body: any }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      const body = JSON.parse(String(init.body));
      bodies.push({ url: String(url), body });
      const known = body.params.account_id === "illia.near";
      return new Response(JSON.stringify(known
        ? { jsonrpc: "2.0", id: body.id, result: { amount: "1", block_height: 1 } }
        : { jsonrpc: "2.0", id: body.id, error: { name: "HANDLER_ERROR", cause: { name: "UNKNOWN_ACCOUNT" } } }),
      { headers: { "content-type": "application/json" } });
    }) as unknown as typeof fetch;
    const near = nearRpc(fetchImpl);
    expect(await near.exists("illia.near")).toBe(true);
    expect(await near.exists("nobody.near")).toBe(false);
    expect(bodies[0]).toEqual({ url: NEAR_RPC, body: { jsonrpc: "2.0", id: "glyf", method: "query",
      params: { request_type: "view_account", finality: "final", account_id: "illia.near" } } });
    const broken = nearRpc((async () => new Response("{}", { status: 503 })) as unknown as typeof fetch, "https://near.example/rpc");
    await expect(broken.exists("illia.near")).rejects.toThrow(/near rpc 503/);
  });

  it("answers a .near account with its chain and address, and keeps the usual shape", async () => {
    const { app } = fakeNear(["alice.near", "pay.alice.near"]);
    const res = await app.inject({ method: "GET", url: "/names/resolve?name=Alice.near" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, found: true, name: "alice.near", chain: "near", address: "alice.near",
      exists: true, addresses: { near: "alice.near" } });
    expect((await app.inject({ method: "GET", url: "/names/resolve?name=pay.alice.near" })).json().exists).toBe(true);
  });

  it("says exists:false (404, found:false) for a .near name NEAR doesn't have, and remembers it", async () => {
    const { app, asked } = fakeNear([]);
    for (let i = 0; i < 2; i++) {
      const res = await app.inject({ method: "GET", url: "/names/resolve?name=nobody.near" });
      expect(res.statusCode).toBe(404);
      expect(res.json()).toEqual({ ok: false, found: false, name: "nobody.near", chain: "near", address: "nobody.near", exists: false });
    }
    expect(asked).toEqual(["nobody.near"]);
  });

  it("takes an implicit account as existing (it can be paid before it's funded) and says whether it's funded", async () => {
    const { app } = fakeNear([]);
    const res = await app.inject({ method: "GET", url: `/names/resolve?name=${IMPLICIT}` });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ found: true, chain: "near", address: IMPLICIT, exists: true, implicit: true, funded: false });
    const down = fakeNear([], true);
    expect((await down.app.inject({ method: "GET", url: `/names/resolve?name=${IMPLICIT}` })).json())
      .toMatchObject({ exists: true, implicit: true });
  });

  it("is a 502 when NEAR doesn't answer for a name, never ENS's answer", async () => {
    const { app } = fakeNear([], true);
    expect((await app.inject({ method: "GET", url: "/names/resolve?name=alice.near" })).statusCode).toBe(502);
  });
});
