import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { FLASH_API, flashRoutes } from "../src/routes/flash.js";

const FUNDER = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
const WETH_BASE = "0x4200000000000000000000000000000000000006";
const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const ORDER_ID = "0b8e6a2c-5d1f-4c3a-9e7b-2a4f6c8d0e1f";

type Call = { url: string; method: string; headers: Record<string, string>; body: any };

/** A stand-in for Flash: answers by path, records each call. */
function setup(answer: (call: Call) => { status?: number; body: unknown }, apiKey = "dpka_test_key") {
  const calls: Call[] = [];
  const app = Fastify();
  flashRoutes(app, {
    apiKey,
    fetchImpl: (async (url: string, init: RequestInit) => {
      const call = { url: String(url), method: String(init.method), headers: init.headers as Record<string, string>,
        body: init.body ? JSON.parse(String(init.body)) : undefined };
      calls.push(call);
      const { status = 200, body } = answer(call);
      return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
    }) as unknown as typeof fetch,
  });
  return { app, calls };
}

/** What Flash's /quote answers for an EVM market buy that spends ETH. */
const QUOTE = {
  quoteId: "q-123", bridgeQuoteId: null, orderType: "market", side: "sell",
  targetAsset: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", contraAsset: USDC_BASE,
  from: { asset: "target", amount: "0.05", notional: "151.20" },
  to: { asset: "contra", amount: "150.90", notional: "150.90" },
  fees: { estimatedFeeNotional: "0.30" }, estimatedPriceImpact: "0.0004", recommendedSlippage: "0.005",
  wrap: { nativeAsset: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", wrappedAsset: WETH_BASE,
    evmTx: { to: WETH_BASE, data: "0xd0e30db0", value: "50000000000000000" }, svmInstructions: null },
  evm: { approveTx: null, permitTypedData: null, orderTypedData: "{\"domain\":{}}" },
  svm: null,
};

describe("POST /flash/quote", () => {
  it("turns symbols into Flash's addresses, adds the key, and returns the quote as Flash wrote it", async () => {
    const { app, calls } = setup(() => ({ body: QUOTE }));
    const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
      targetChain: "base", contraChain: "base", target: "ETH", contra: "usdc",
      side: "sell", qty: "0.05", orderType: "market", funderAddress: FUNDER,
    } });
    expect(res.statusCode).toBe(200);
    expect(calls[0].url).toBe(`${FLASH_API}/quote`);
    expect(calls[0].headers["x-definitive-api-key"]).toBe("dpka_test_key");
    expect(calls[0].body).toMatchObject({ targetAsset: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      contraAsset: USDC_BASE, side: "sell", qty: "0.05" });
    const body = res.json();
    expect(body).toMatchObject({ ok: true, quoteId: "q-123", evm: QUOTE.evm, wrap: QUOTE.wrap });
    expect(body.tokens.target).toMatchObject({ symbol: "ETH", native: true });
    // The submit body: the spent ETH becomes the WETH the quote priced.
    expect(body.order).toMatchObject({ targetAsset: WETH_BASE, contraAsset: USDC_BASE, quoteId: "q-123",
      evmOrderTypedData: "{\"domain\":{}}", funderAddress: FUNDER, orderType: "market" });
    expect(body.order).not.toHaveProperty("bridgeQuoteId");
    expect(res.body).not.toContain("dpka_test_key");
  });

  it("takes `chain` for both sides and a stop-limit as a stop with a limit", async () => {
    const { app, calls } = setup(() => ({ body: { ...QUOTE, orderType: "stop-loss" } }));
    const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
      chain: "base", target: "WETH", contra: "USDC", side: "sell", qty: "0.05", orderType: "stop-loss-limit",
      limitNotionalPrice: "2950", triggers: [{ notionalPrice: "3000", triggerType: "lower" }], funderAddress: FUNDER,
    } });
    expect(res.statusCode).toBe(200);
    expect(calls[0].body).toMatchObject({ targetChain: "base", contraChain: "base", targetAsset: WETH_BASE,
      orderType: "stop-loss", limitNotionalPrice: "2950" });
  });

  it("passes an attached bracket in Flash's shape and echoes its signing material into the order", async () => {
    const { app, calls } = setup(() => ({ body: { ...QUOTE, side: "buy",
      attachedBracket: { evm: { approveTx: null, permitTypedData: "{\"permit\":1}", orderTypedData: "{\"pair\":1}" },
        svm: null, salt: "0xabc", deadline: "1799999999", signedMaxFromAmount: "52500000000000000" } } }));
    const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
      chain: "base", target: "WETH", contra: "USDC", side: "buy", qty: "100", orderType: "market", funderAddress: FUNDER,
      attachedBracket: { takeProfit: { notionalPrice: "4500" }, stopLoss: { notionalPrice: "3000" } },
    } });
    expect(res.statusCode).toBe(200);
    expect(calls[0].body.attachedBracket).toEqual({ takeProfit: { notionalPrice: "4500" }, stopLoss: { notionalPrice: "3000" } });
    expect(res.json().order.attachedBracket).toEqual({
      takeProfit: { notionalPrice: "4500" }, stopLoss: { notionalPrice: "3000" },
      deadline: "1799999999", signedMaxFromAmount: "52500000000000000", salt: "0xabc",
      evmPermitTypedData: "{\"permit\":1}",
    });
  });

  it("spends native SOL with Flash's native-SOL intent and echoes the Solana nonce", async () => {
    const { app, calls } = setup(() => ({ body: { ...QUOTE, evm: null, wrap: null,
      svm: { orderMessage: "DFS|m=So1|t=1|h=x", nonce: "42", deadline: "1799999999", ataSetupIxs: null,
        delegateIx: null, sponsoredDelegateTx: null } } }));
    const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
      chain: "solana", target: "SOL", contra: "USDC", side: "sell", qty: "1", orderType: "market",
      funderAddress: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj",
    } });
    expect(res.statusCode).toBe(200);
    expect(calls[0].body).toMatchObject({ targetAsset: "So11111111111111111111111111111111111111112",
      contraAsset: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", svmUseNativeSOL: true });
    expect(res.json().order).toMatchObject({ svmNonce: "42", svmDeadline: "1799999999" });
  });

  it("refuses what Flash's docs rule out, before calling Flash", async () => {
    const { app, calls } = setup(() => ({ body: QUOTE }));
    const bad = [
      { orderType: "limit" },
      { orderType: "market", limitNotionalPrice: "3000" },
      { orderType: "stop-loss", triggers: [{ notionalPrice: "3000", triggerType: "upper" }] },
      { orderType: "bracket", triggers: [{ notionalPrice: "4500", triggerType: "upper" }] },
      { orderType: "twap" },
      { orderType: "trailing-stop" },
      { orderType: "dca" },
      { orderType: "market", contraChain: "arbitrum" },
      { orderType: "stop-limit", triggers: [{ notionalPrice: "3000", triggerType: "lower" }] },
      { orderType: "market", target: "NOTACOIN" },
    ];
    for (const extra of bad) {
      const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
        targetChain: "base", contraChain: "base", target: "ETH", contra: "USDC", side: "sell", qty: "0.05",
        funderAddress: FUNDER, ...extra } });
      expect(res.statusCode, JSON.stringify(extra)).toBe(400);
    }
    expect(calls).toHaveLength(0);
  });

  it("passes on Flash's own error, and is 503 without a key", async () => {
    const { app } = setup(() => ({ status: 400, body: { error: { code: "INVALID_ARGUMENT", message: "qty below minimum" } } }));
    const res = await app.inject({ method: "POST", url: "/flash/quote", payload: {
      chain: "base", target: "ETH", contra: "USDC", side: "sell", qty: "0.000001", orderType: "market" } });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ ok: false, error: "qty below minimum", code: "INVALID_ARGUMENT" });
    const none = setup(() => ({ body: {} }), "");
    expect((await none.app.inject({ method: "GET", url: "/flash/search?query=eth" })).statusCode).toBe(503);
  });
});

describe("Flash orders", () => {
  const order = { targetChain: "base", contraChain: "base", targetAsset: WETH_BASE, contraAsset: USDC_BASE,
    side: "sell", qty: "0.05", orderType: "market", funderAddress: FUNDER, quoteId: "q-123",
    userSignature: "0xsig", evmOrderTypedData: "{\"domain\":{}}" };

  it("submits a signed order as is", async () => {
    const { app, calls } = setup(() => ({ body: { orderId: ORDER_ID } }));
    const res = await app.inject({ method: "POST", url: "/flash/order", payload: order });
    expect(res.json()).toEqual({ ok: true, orderId: ORDER_ID });
    expect(calls[0].body).toEqual(order);
  });

  it("refuses an order without a signature, or spending the native placeholder", async () => {
    const { app, calls } = setup(() => ({ body: {} }));
    const { userSignature: _, ...unsigned } = order;
    expect((await app.inject({ method: "POST", url: "/flash/order", payload: unsigned })).statusCode).toBe(400);
    expect((await app.inject({ method: "POST", url: "/flash/order", payload: { ...order,
      targetAsset: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" } })).statusCode).toBe(400);
    expect(calls).toHaveLength(0);
  });

  it("lists a wallet's orders, never everyone's, and fetches one by id", async () => {
    const { app, calls } = setup(() => ({ body: { orders: [], nextPageToken: null } }));
    expect((await app.inject({ method: "GET", url: "/flash/orders" })).statusCode).toBe(400);
    await app.inject({ method: "GET", url: `/flash/orders?funderAddress=${FUNDER}&statuses=ORDER_STATUS_OPEN&pageSize=500` });
    expect(calls[0].url).toBe(`${FLASH_API}/orders?funderAddress=${FUNDER}&statuses=ORDER_STATUS_OPEN&pageSize=200`);
    await app.inject({ method: "GET", url: `/flash/orders?funderAddress=${FUNDER}&orderId=${ORDER_ID}` });
    expect(calls[1].url).toBe(`${FLASH_API}/orders/${ORDER_ID}?funderAddress=${FUNDER}`);
    expect((await app.inject({ method: "GET", url: `/flash/orders?funderAddress=${FUNDER}&orderId=nope` })).statusCode).toBe(400);
  });

  it("cancels with the funder's signed message, one or many", async () => {
    const { app, calls } = setup(() => ({ body: { ok: true } }));
    const signed = { cancelMessage: `Definitive Flash v1 — Cancel Order\nOrder: ${ORDER_ID}`, userSignature: "0xsig" };
    const one = await app.inject({ method: "POST", url: `/flash/orders/${ORDER_ID}/cancel`, payload: signed });
    expect(one.json()).toEqual({ ok: true });
    expect(calls[0]).toMatchObject({ url: `${FLASH_API}/orders/${ORDER_ID}/cancel`, method: "POST", body: signed });
    await app.inject({ method: "POST", url: "/flash/orders/cancel", payload: { ...signed, orderIds: [ORDER_ID] } });
    expect(calls[1].url).toBe(`${FLASH_API}/orders/cancel`);
    expect((await app.inject({ method: "POST", url: `/flash/orders/${ORDER_ID}/cancel`, payload: {} })).statusCode).toBe(400);
  });

  it("searches assets and carries a signed setup transaction", async () => {
    const { app, calls } = setup(call => ({ body: call.url.includes("/search") ? { assets: [{ symbol: "PEPE" }] } : { status: "pending" } }));
    const search = await app.inject({ method: "GET", url: "/flash/search?query=pepe&chain=base&limit=99" });
    expect(search.json()).toEqual({ ok: true, assets: [{ symbol: "PEPE" }] });
    expect(calls[0].url).toBe(`${FLASH_API}/search?query=pepe&chain=base&limit=25`);
    const setupTx = await app.inject({ method: "POST", url: "/flash/setup-transaction", payload: { signedSetupTx: "0x02f8" } });
    expect(setupTx.json()).toEqual({ ok: true, status: "pending" });
  });

  it("is a 502 when Flash doesn't answer", async () => {
    const app = Fastify();
    flashRoutes(app, { apiKey: "k", fetchImpl: (async () => { throw new Error("ETIMEDOUT"); }) as unknown as typeof fetch });
    expect((await app.inject({ method: "GET", url: `/flash/orders?funderAddress=${FUNDER}` })).statusCode).toBe(502);
  });
});
