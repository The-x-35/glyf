import Fastify from "fastify";
import { decodeFunctionData, getAddress, parseAbi } from "viem";
import { describe, expect, it } from "vitest";
import { defaultVault, EARN_VAULTS, EarnRates, earnQuote, earnVaults, KAMINO_API, MORPHO_API, vaultOf } from "../src/lib/nearearn.js";
import { NearIntents, ONECLICK, type IntentToken } from "../src/lib/nearintents.js";
import { nearRoutes } from "../src/routes/near.js";

/** Earn through 1Click (lib/nearearn.ts), with stand-ins for 1Click, Morpho's
 *  GraphQL and Kamino's REST: no network. */

const NOW = Date.parse("2026-11-13T00:00:00Z");
const BASE_USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const GT = "0x0bb69b79bc829e1cfcc34a740110886d98d2bd14";
const KV_MINT = "5EBsGgVTubrd7ShJgE89k6nC2bnLzqGCjXb2ejrhtdBK";
const DEPOSIT = "0x76b4c56085ED136a8744D52bE956396624a730E8";
const MINE = "0x1111111111111111111111111111111111111111";
const PHANTOM = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU";

/** /v0/tokens as it listed Earn's receipt tokens on 2026-11-13 (prices as
 *  1Click gives them: per base unit of an 18-decimal share, oddly small). */
const TOKENS: IntentToken[] = [
  { assetId: `nep141:base-${BASE_USDC}.omft.near`, decimals: 6, blockchain: "base", symbol: "USDC", price: 1, contractAddress: BASE_USDC },
  { assetId: "nep141:sol.omft.near", decimals: 9, blockchain: "sol", symbol: "SOL", price: 80 },
  { assetId: "nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near", decimals: 6, blockchain: "sol", symbol: "USDC",
    price: 1, contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" },
  { assetId: `nep141:base-${GT}.omft.near`, decimals: 18, blockchain: "base", symbol: "gtUSDCp", price: 1.1179e-6, contractAddress: GT },
  { assetId: "nep141:sol-0xa69aa1bcb03a369e338156a8718ad60271145803.omdep.near", decimals: 9, blockchain: "sol", symbol: "kV-gtSOLb",
    price: 85.9, contractAddress: KV_MINT },
];

type Opts = { quote?: (body: any) => Response; morpho?: () => Response; kamino?: () => Response };

function fakes(opts: Opts = {}) {
  const calls: { url: string; body?: any }[] = [];
  const ok = (json: unknown) => new Response(JSON.stringify(json), { headers: { "content-type": "application/json" } });
  const fetchImpl = (async (url: string, init: RequestInit = {}) => {
    const body = init.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url: String(url), body });
    if (String(url) === MORPHO_API) {
      if (opts.morpho) return opts.morpho();
      return ok({ data: { vaultByAddress: { name: "Gauntlet USDC Prime", state: { netApy: 0.045008528940505894, apy: 0.045008528940505894 } } } });
    }
    if (String(url).startsWith(KAMINO_API)) {
      if (opts.kamino) return opts.kamino();
      return ok({ apy: "0.04243524551652533", apy7d: "0.0444", sharePrice: "86.13", tokensPerShare: "1.0568" });
    }
    const u = new URL(String(url));
    if (u.origin !== ONECLICK) throw new Error(`unexpected ${url}`);
    if (u.pathname === "/v0/tokens") return ok(TOKENS);
    if (u.pathname === "/v0/quote") {
      if (opts.quote) return opts.quote(body);
      // Prices as the live quotes went: 20 USDC is 17,802,051 gtUSDCp
      // shares; 0.2 SOL is 0.1859 kV-gtSOLb.
      const amount = BigInt(body.amount);
      const table: Record<string, (n: bigint) => bigint> = {
        [`${TOKENS[0].assetId}>${TOKENS[3].assetId}`]: n => n * 890_102_583_694_601_035n / 1000n,
        [`${TOKENS[3].assetId}>${TOKENS[0].assetId}`]: n => n * 1000n / 908_000_000_000_000_000n,
        [`${TOKENS[1].assetId}>${TOKENS[4].assetId}`]: n => n * 929n / 1000n,
        [`${TOKENS[2].assetId}>${TOKENS[3].assetId}`]: n => n * 890_102_583_694_601_035n / 1000n,
      };
      const rate = table[`${body.originAsset}>${body.destinationAsset}`] ?? table[`${body.destinationAsset}>${body.originAsset}`];
      if (!rate) return new Response(JSON.stringify({ message: "No liquidity available" }), { status: 400 });
      const [amountIn, amountOut] = body.swapType === "EXACT_INPUT" ? [amount, rate(amount)]
        : [amount * 908_000_000_000_000_000n / 1000n, amount];
      return ok({ quote: {
        amountIn: amountIn.toString(), amountInUsd: "19.990900000000", amountOut: amountOut.toString(), amountOutUsd: "19.901042571707",
        minAmountOut: (amountOut * 99n / 100n).toString(), timeEstimate: 52,
        ...(body.dry ? {} : { depositAddress: body.originAsset.includes(":sol") ? "Dep0sitSo1anaAddre55xxxxxxxxxxxxxxxxxxxxxx1" : DEPOSIT,
          deadline: "2026-11-14T00:00:00.000Z" }),
      }, quoteRequest: body });
    }
    throw new Error(`unexpected ${url}`);
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

function earn(opts: Opts = {}) {
  const f = fakes(opts);
  return { ...f, intents: new NearIntents({ fetchImpl: f.fetchImpl, jwt: () => "", now: () => NOW }),
    rates: new EarnRates({ fetchImpl: f.fetchImpl, now: () => NOW }) };
}

describe("Earn vaults", () => {
  it("knows each vault by id, receipt symbol, asset id or protocol, and where a coin earns by default", () => {
    expect(vaultOf("gtUSDCp")?.id).toBe("gtusdcp");
    expect(vaultOf("morpho")?.id).toBe("gtusdcp");
    expect(vaultOf("kamino")?.chain).toBe("solana");
    expect(vaultOf(TOKENS[4].assetId)?.id).toBe("kamino-sol");
    expect(vaultOf("aave")).toBeNull();
    expect(defaultVault("usdc")?.id).toBe("gtusdcp");
    expect(defaultVault("$SOL")?.id).toBe("kamino-sol");
    expect(defaultVault("ETH")).toBeNull();
    // Morpho's rate is of the vault 1Click's wrapper holds, not the wrapper.
    expect(EARN_VAULTS[0].apySource).toEqual({ kind: "morpho", address: "0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61", chainId: 8453 });
  });

  it("lists the vaults 1Click still lists, with each one's APY from its own protocol", async () => {
    const e = earn();
    const vaults = await earnVaults(e.intents, e.rates);
    // Taler isn't in this token list, so it isn't offered.
    expect(vaults.map(v => v.id)).toEqual(["gtusdcp", "kamino-sol"]);
    expect(vaults[0]).toMatchObject({ name: "Gauntlet USDC Prime", protocol: "Morpho", chain: "base", chainName: "Base", underlying: "USDC",
      receipt: "gtUSDCp", apy: 4.5, apySource: "Morpho", apyBasis: "net APY after the vault's fees", default: true });
    expect(vaults[1]).toMatchObject({ protocol: "Kamino", chain: "solana", underlying: "SOL", apy: 4.24, apySource: "Kamino" });
    const morpho = e.calls.find(c => c.url === MORPHO_API)!;
    expect(morpho.body.variables).toEqual({ a: "0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61", c: 8453 });
    expect(e.calls.some(c => c.url === `${KAMINO_API}/kvaults/vaults/DcCRSdUMgAt6ZMeuL4BJAsZmJgND2LQd74Zq4z6ckhpg/metrics`)).toBe(true);
  });

  it("leaves the APY out, never guessed, when the protocol's API fails or answers nonsense; and keeps a rate ten minutes", async () => {
    const f = fakes({ morpho: () => new Response("{}", { status: 500 }), kamino: () => new Response(JSON.stringify({ apy: "7" })) });
    const rates = new EarnRates({ fetchImpl: f.fetchImpl, now: () => NOW });
    const vaults = await earnVaults(new NearIntents({ fetchImpl: f.fetchImpl, jwt: () => "", now: () => NOW }), rates);
    expect(vaults.map(v => v.apy)).toEqual([null, null]);
    expect(vaults[0].apySource).toBeNull();
    const ok = earn();
    await ok.rates.apy(EARN_VAULTS[0]);
    await ok.rates.apy(EARN_VAULTS[0]);
    expect(ok.calls.filter(c => c.url === MORPHO_API)).toHaveLength(1);
    // A vault with no public rate API is never asked.
    expect(await ok.rates.apy(vaultOf("taler-usdc")!)).toBeNull();
  });
});

describe("Earn quotes", () => {
  const ERC20 = parseAbi(["function transfer(address to, uint256 amount) returns (bool)"]);

  it("puts USDC on Base into Gauntlet USDC Prime as a /near/quote with a plain ERC-20 deposit", async () => {
    const e = earn();
    const q = await earnQuote(e.intents, e.rates, { direction: "in", coin: "usdc", amount: "20", refundTo: MINE, recipient: MINE });
    expect(q).toMatchObject({ ok: true, kind: "earn", direction: "in", dry: false, venue: "NEAR Intents", exact: "in",
      sell: { symbol: "USDC", chain: "base" }, buy: { symbol: "gtUSDCp", chain: "base" }, amountIn: "20", amountInBase: "20000000",
      depositAddress: DEPOSIT, recipient: MINE, refundTo: MINE, timeSeconds: 52,
      vault: { id: "gtusdcp", apy: 4.5 }, words: "≈ $19.90 in Gauntlet USDC Prime at 4.5% APY" });
    expect(q.deposit).toMatchObject({ kind: "erc20", chainId: 8453, to: getAddress(BASE_USDC), amountBase: "20000000" });
    expect(decodeFunctionData({ abi: ERC20, data: (q.deposit as any).data }).args).toEqual([DEPOSIT, 20000000n]);
    const sent = e.calls.find(c => c.url.endsWith("/v0/quote"))!.body;
    expect(sent).toMatchObject({ swapType: "EXACT_INPUT", originAsset: TOKENS[0].assetId, destinationAsset: TOKENS[3].assetId,
      recipient: MINE, recipientType: "DESTINATION_CHAIN", refundTo: MINE, refundType: "ORIGIN_CHAIN", dry: false });
  });

  it("puts SOL into Kamino with a native SOL deposit, and USDC on Solana into the Base vault", async () => {
    const e = earn();
    const sol = await earnQuote(e.intents, e.rates, { direction: "in", coin: "SOL", amount: "0.2", refundTo: PHANTOM, recipient: PHANTOM });
    expect(sol).toMatchObject({ vault: { id: "kamino-sol", apy: 4.24 }, sell: { symbol: "SOL", chain: "solana" },
      buy: { symbol: "kV-gtSOLb", chain: "solana" }, amountOut: "0.1858" });
    expect(sol.deposit).toMatchObject({ kind: "sol", lamports: "200000000" });
    const cross = await earnQuote(e.intents, e.rates, { direction: "in", coin: "USDC", chain: "solana", amount: "20", refundTo: PHANTOM, recipient: MINE });
    expect(cross).toMatchObject({ sell: { chain: "solana" }, buy: { symbol: "gtUSDCp", chain: "base" } });
    expect(cross.deposit).toMatchObject({ kind: "spl", mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" });
  });

  it("is a dry preview without both addresses", async () => {
    const e = earn();
    const q = await earnQuote(e.intents, e.rates, { direction: "in", coin: "USDC", amount: "50" });
    expect(q).toMatchObject({ dry: true, depositAddress: null, deposit: null, recipient: null, refundTo: null });
  });

  it("takes USDC back out: exactly the amount asked, paid for in shares, or every share the app sends", async () => {
    const e = earn();
    const exact = await earnQuote(e.intents, e.rates, { direction: "out", coin: "USDC", amount: "10", refundTo: MINE, recipient: MINE });
    expect(exact).toMatchObject({ direction: "out", exact: "out", sell: { symbol: "gtUSDCp" }, buy: { symbol: "USDC", chain: "base" },
      amountOut: "10", words: "10 USDC back on Base from Gauntlet USDC Prime" });
    // The shares go to the deposit address as an ERC-20 transfer of gtUSDCp.
    expect(exact.deposit).toMatchObject({ kind: "erc20", token: getAddress(GT) });
    const all = await earnQuote(e.intents, e.rates, { direction: "out", coin: "USDC", shares: "17802051673892020712891611",
      refundTo: MINE, recipient: MINE });
    expect(all).toMatchObject({ exact: "in", amountInBase: "17802051673892020712891611", amountIn: "17802051.673892020712891611" });
    const body = e.calls.filter(c => c.url.endsWith("/v0/quote")).at(-1)!.body;
    expect(body).toMatchObject({ swapType: "EXACT_INPUT", originAsset: TOKENS[3].assetId, destinationAsset: TOKENS[0].assetId });
  });

  it("says what's wrong in plain words", async () => {
    const e = earn();
    const fail = (input: Parameters<typeof earnQuote>[2]) => earnQuote(e.intents, e.rates, input).then(() => "", (err: Error) => err.message);
    expect(await fail({ direction: "in", coin: "DOGE", amount: "5" })).toBe("Earn takes USDC or SOL, not DOGE");
    expect(await fail({ direction: "in", coin: "USDC", amount: "5", vault: "aave" })).toBe("Glyf doesn't know that vault");
    expect(await fail({ direction: "in", coin: "USDC", amount: "5", recipient: PHANTOM })).toBe("Gauntlet USDC Prime's shares need your Base address");
    expect(await fail({ direction: "out", coin: "USDC", amount: "5", recipient: PHANTOM })).toBe("The payout needs your Base address");
    expect(await fail({ direction: "out", coin: "USDC" })).toBe("amount?");
    expect(await fail({ direction: "out", coin: "USDC", shares: "0" })).toBe("shares?");
    expect(await fail({ direction: "in", coin: "USDC", chain: "fantom", amount: "5" })).toBe("NEAR Intents isn't on fantom");
    const dry = earn({ quote: () => new Response(JSON.stringify({ message: "No liquidity available" }), { status: 400 }) });
    expect(await earnQuote(dry.intents, dry.rates, { direction: "in", coin: "USDC", amount: "5" }).catch((err: Error) => err.message))
      .toBe("NEAR Intents can't put that into Gauntlet USDC Prime right now");
  });
});

describe("GET /near/earn/vaults and POST /near/earn/quote", () => {
  function app(opts: Opts = {}) {
    const f = fakes(opts);
    const a = Fastify();
    nearRoutes(a, { fetchImpl: f.fetchImpl, jwt: () => "", now: () => NOW });
    return { app: a, ...f };
  }

  it("lists the vaults and quotes a deposit in /near/quote's shape", async () => {
    const { app: a } = app();
    const list = await a.inject({ method: "GET", url: "/near/earn/vaults" });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toMatchObject({ ok: true, venue: "NEAR Intents", vaults: [{ id: "gtusdcp", apy: 4.5 }, { id: "kamino-sol", apy: 4.24 }] });
    const q = await a.inject({ method: "POST", url: "/near/earn/quote", payload: { coin: "USDC", amount: "20", refundTo: MINE, recipient: MINE } });
    expect(q.statusCode).toBe(200);
    expect(q.json()).toMatchObject({ ok: true, kind: "earn", direction: "in", dry: false, depositAddress: DEPOSIT,
      deposit: { kind: "erc20" }, vault: { id: "gtusdcp", name: "Gauntlet USDC Prime", apy: 4.5 } });
    const out = await a.inject({ method: "POST", url: "/near/earn/quote", payload: { coin: "USDC", amount: "10", direction: "out" } });
    expect(out.json()).toMatchObject({ ok: true, direction: "out", dry: true, exact: "out" });
  });

  it("answers bad bodies with a 400 in words", async () => {
    const { app: a } = app();
    const bad = async (payload: object) => {
      const r = await a.inject({ method: "POST", url: "/near/earn/quote", payload });
      return [r.statusCode, r.json().error];
    };
    expect(await bad({ coin: "USDC", amount: "-1" })).toEqual([400, "amount?"]);
    expect(await bad({ coin: "USDC", amount: "1", direction: "sideways" })).toEqual([400, expect.any(String)]);
    expect(await bad({ coin: "PEPE", amount: "1" })).toEqual([400, "Earn takes USDC or SOL, not PEPE"]);
  });
});
