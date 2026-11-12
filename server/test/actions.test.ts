import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { ACTION_GUIDE, ACTION_TOOLS, checkAction, mayAct, mockAction } from "../src/lib/actions.js";
import { READING_PROMPT, firstObject, parseActionReading } from "../src/lib/reading.js";
import { signedInApp } from "./helpers.js";

beforeAll(() => {
  env.mockAI = true;
});

describe("checking a model's action", () => {
  it("keeps a DCA with clean values and writes the chip's words itself", () => {
    expect(checkAction({ tool: "trade.dca", params: { asset: "eth", every: "$20", period: "month", junk: 1 } }))
      .toEqual({ tool: "trade.dca", label: "DCA $20 of ETH monthly · Flash", params: { asset: "ETH", every: "20", period: "month" } });
    expect(checkAction({ tool: "trade.dca", params: { asset: "btc", every: 50, period: "week", periods: 13, chain: "Base" } }))
      .toMatchObject({ params: { asset: "WBTC", every: "50", period: "week", periods: 13, chain: "base" } });
  });

  it("drops an unknown tool, a bad value or a missing one", () => {
    expect(checkAction({ tool: "trade.yolo", params: {} })).toBeNull();
    expect(checkAction({ tool: "trade.dca", params: { asset: "doge", every: 20, period: "month" } })).toBeNull();
    expect(checkAction({ tool: "trade.dca", params: { asset: "usdc", every: 20, period: "month" } })).toBeNull();
    expect(checkAction({ tool: "trade.dca", params: { asset: "eth", every: -5, period: "month" } })).toBeNull();
    expect(checkAction({ tool: "trade.dca", params: { asset: "eth", every: 5, period: "fortnight" } })).toBeNull();
    expect(checkAction({ tool: "trade.flash", params: { type: "stop-loss", asset: "eth" } })).toBeNull();
    expect(checkAction({ tool: "trade.flash", params: { type: "bracket", asset: "eth", price: 3000, stopPrice: 4000 } })).toBeNull();
    expect(checkAction({ tool: "trade.swap", params: { sell: "eth", buy: "eth" } })).toBeNull();
    // Sends to names and Whitechain pay requests aren't this branch's tools.
    expect(checkAction({ tool: "send", params: { to: "arpit.eth", amount: 5, token: "usdc" } })).toBeNull();
    expect(checkAction({ tool: "pay", params: { amount: 5 } })).toBeNull();
    expect(checkAction({ tool: "search", params: { query: "" } })).toBeNull();
    expect(checkAction(null)).toBeNull();
    expect(checkAction("trade.dca")).toBeNull();
  });

  it("labels each kind of tool", () => {
    expect(checkAction({ tool: "trade.flash", params: { type: "stop-loss", asset: "eth", price: 3000 } })?.label)
      .toBe("Stop-loss ETH at $3,000 · Flash");
    expect(checkAction({ tool: "trade.swap", params: { sell: "usdc", buy: "eth", amount: 20, usd: true } })?.label)
      .toBe("Buy $20 of ETH · Uniswap");
    expect(checkAction({ tool: "calendar.event", params: { title: "Dinner with Sam", when: "fri 8pm" } })?.label)
      .toBe("Add Dinner with Sam · fri 8pm");
    expect(checkAction({ tool: "meet.link", params: {} })?.label).toBe("Insert a Meet link");
    expect(checkAction({ tool: "youtube", params: { query: "dune 2 trailer" } })?.label).toBe("YouTube: dune 2 trailer");
    expect(checkAction({ tool: "translate", params: { to: "spanish" } })?.label).toBe("Translate to Spanish");
  });
});

describe("the prompt", () => {
  it("lists every tool only when the phone asked for actions", () => {
    const withActions = READING_PROMPT("put 20 bucks in eth every month", [], true);
    for (const tool of ACTION_TOOLS.filter(t => !["rewrite", "youtube", "shorts", "maps"].includes(t))) {
      expect(withActions, tool).toContain(tool);
    }
    expect(withActions).toContain("search|youtube|shorts|maps");
    expect(withActions).toContain(ACTION_GUIDE);
    // Old phones: the very same prompt as before.
    expect(READING_PROMPT("put 20 bucks in eth every month", [])).not.toContain("action");
    expect(READING_PROMPT("put 20 bucks in eth every month", [])).toBe(READING_PROMPT("put 20 bucks in eth every month", [], false));
  });

  it("reads nested JSON, and keeps the reading when the action is bad", () => {
    expect(firstObject('sure: {"intent":"rewrite","action":{"tool":"meet.link","params":{}}} ok')).toBe(
      '{"intent":"rewrite","action":{"tool":"meet.link","params":{}}}');
    expect(firstObject('{"a":"}{"}')).toBe('{"a":"}{"}');
    expect(parseActionReading('{"intent":"rewrite","action":{"tool":"trade.dca","params":{"asset":"eth","every":20,"period":"month"}}}', "x", []))
      .toMatchObject({ intent: "rewrite", action: { tool: "trade.dca", params: { asset: "ETH" } } });
    expect(parseActionReading('{"intent":"rewrite","action":{"tool":"rm -rf","params":{}}}', "x", []))
      .toEqual({ intent: "rewrite", field: null, action: null });
    expect(parseActionReading("no json here", "x", [])).toBeNull();
  });

  it("looks again only at words a tool might act on", () => {
    expect(mayAct("can we do dinner fri at 8")).toBe(true);
    expect(mayAct("put 20 bucks in eth every month")).toBe(true);
    expect(mayAct("haha that was so funny")).toBe(false);
  });

  it("has a stand-in for MOCK_AI", () => {
    expect(mockAction("i want to put 20 bucks into eth every month")?.tool).toBe("trade.dca");
    expect(mockAction("lets hop on a call")?.tool).toBe("meet.link");
    expect(mockAction("ok sounds good")).toBeNull();
  });
});

describe("POST /suggest with actions", () => {
  const ask = (app: ReturnType<typeof signedInApp>, text: string, extra: Record<string, unknown> = {}) =>
    app.inject({ method: "POST", url: "/suggest", payload: { text, deviceId: "actions-test-0001", ...extra } });

  it("adds an action for a phone that asks", async () => {
    const app = signedInApp();
    const res = (await ask(app, "i want to put 20 bucks into eth every month", { actions: true })).json();
    expect(res.ok).toBe(true);
    expect(res.action).toEqual({ tool: "trade.dca", label: "DCA $20 of ETH monthly · Flash",
      params: { asset: "ETH", every: "20", period: "month" } });
    // Cached: the same answer the second time.
    expect((await ask(app, "i want to put 20 bucks into eth every month", { actions: true })).json().action?.tool).toBe("trade.dca");
  });

  it("gives an old phone exactly what it got before: no action key", async () => {
    const app = signedInApp();
    const old = (await ask(app, "i want to put 20 bucks into eth every month")).json();
    expect(old).not.toHaveProperty("action");
    expect(Object.keys(old).sort()).toEqual(["ok", "suggestion"]);
  });

  it("says no action when nothing fits", async () => {
    const app = signedInApp();
    const res = (await ask(app, "ok will send the deck before six tmrw", { actions: true })).json();
    expect(res.suggestion).toMatchObject({ intent: "rewrite" });
    expect(res.action).toBeNull();
  });
});

describe("grounding", () => {
  it("drops a chain the words never named, keeps one they did", async () => {
    const { groundAction } = await import("../src/lib/actions.js");
    const sl = checkAction({ tool: "trade.flash", params: { type: "stop-loss", asset: "eth", price: 3000, chain: "ethereum" } });
    expect(groundAction(sl, "sell my eth if it falls under 3k")?.params).not.toHaveProperty("chain");
    expect(groundAction(sl, "sell my eth on ethereum if it falls under 3k")?.params.chain).toBe("ethereum");
    const base = checkAction({ tool: "trade.dca", params: { asset: "eth", every: 20, period: "month", chain: "base" } });
    expect(groundAction(base, "dca 20 bucks into eth monthly on base")?.params.chain).toBe("base");
    expect(groundAction(base, "dca 20 bucks into eth monthly")?.params.chain).toBeUndefined();
    expect(parseActionReading('{"action":{"tool":"trade.flash","params":{"type":"stop-loss","asset":"ETH","price":3000,"chain":"ethereum"}}}',
      "sell my eth if it falls under 3k", [])?.action?.params).not.toHaveProperty("chain");
  });
});
