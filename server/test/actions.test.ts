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

describe("NEAR Intents actions", () => {
  const ground = async (raw: unknown, text: string) => {
    const { groundAction } = await import("../src/lib/actions.js");
    return groundAction(checkAction(raw), text);
  };

  it("swaps across chains Uniswap can't reach, and leaves the rest to Uniswap", async () => {
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "sol", amount: 20, sellChain: "base" } }))
      .toEqual({ tool: "near.swap", label: "Swap 20 USDC → SOL · NEAR Intents",
        params: { sell: "USDC", buy: "SOL", amount: "20", sellChain: "base" } });
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "btc", amount: 50 } })?.label)
      .toBe("Swap 50 USDC → BTC · NEAR Intents");
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "usdc", amount: 50, buyChain: "solana" } })?.label)
      .toBe("Move 50 USDC to Solana · NEAR Intents");
    // Both sides on EVM chains, or the same coin on the same chain: not NEAR Intents' job.
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "eth", amount: 20 } })).toBeNull();
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "usdc", buyChain: "arbitrum" } })).toBeNull();
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "usdc" } })).toBeNull();
    expect(checkAction({ tool: "near.swap", params: { sell: "pepe", buy: "sol" } })).toBeNull();
    expect(checkAction({ tool: "near.swap", params: { sell: "usdc", buy: "sol", sellChain: "fantom" } })).toBeNull();
  });

  it("sends to a .near name, an implicit account, or a Bitcoin or Zcash address", () => {
    expect(checkAction({ tool: "near.send", params: { to: "alice.near", amount: 5, coin: "usdc" } }))
      .toEqual({ tool: "near.send", label: "Send 5 USDC to alice.near · NEAR Intents",
        params: { to: "alice.near", amount: "5", coin: "USDC" } });
    expect(checkAction({ tool: "near.send", params: { to: "bob.near", amount: 10, with: "sol" } })?.label)
      .toBe("Send 10 USDC to bob.near with SOL · NEAR Intents");
    expect(checkAction({ tool: "near.send", params: { to: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", amount: 0.001 } }))
      .toMatchObject({ label: "Send 0.001 BTC to bc1q…0wlh · NEAR Intents", params: { coin: "BTC" } });
    expect(checkAction({ tool: "near.send", params: { to: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", amount: 5, coin: "usdc" } })).toBeNull();
    expect(checkAction({ tool: "near.send", params: { to: "arpit.eth", amount: 5 } })).toBeNull();
    expect(checkAction({ tool: "near.send", params: { to: "0x1111111111111111111111111111111111111111", amount: 5 } })).toBeNull();
    expect(checkAction({ tool: "near.send", params: { to: "alice.near" } })).toBeNull();
  });

  it("asks for money with a pay link, saying each person's share", () => {
    expect(checkAction({ tool: "near.request", params: { amount: "22.50", chain: "solana", note: "dinner" } }))
      .toEqual({ tool: "near.request", label: "Request $22.50 on Solana · NEAR Intents",
        params: { amount: "22.5", chain: "solana", note: "dinner" } });
    expect(checkAction({ tool: "near.request", params: { amount: 90, count: 4, us: true, note: "dinner" } })?.label)
      .toBe("Request $22.50 each · NEAR Intents");
    expect(checkAction({ tool: "near.request", params: { amount: 22.5, each: true } })?.label).toBe("Request $22.50 each · NEAR Intents");
    expect(checkAction({ tool: "near.request", params: { amount: 0.01, coin: "btc" } })?.label).toBe("Request 0.01 BTC · NEAR Intents");
    expect(checkAction({ tool: "near.request", params: { amount: 20, note: "<script>" } })).toBeNull();
    expect(checkAction({ tool: "near.request", params: { amount: 20, count: 1 } })).toBeNull();
    expect(checkAction({ tool: "near.request", params: {} })).toBeNull();
  });

  it("keeps only what the words said: amounts, names, chains, headcounts and notes", async () => {
    const owe = "you owe me 22.50 for dinner, I'm on solana";
    expect(await ground({ tool: "near.request", params: { amount: 22.5, chain: "solana", note: "dinner" } }, owe))
      .toMatchObject({ label: "Request $22.50 on Solana · NEAR Intents", params: { amount: "22.5", chain: "solana", note: "dinner" } });
    // An amount nobody typed is no request at all.
    expect(await ground({ tool: "near.request", params: { amount: 25 } }, owe)).toBeNull();
    // A chain, a note and a headcount the model made up go; the request stays.
    const made = await ground({ tool: "near.request", params: { amount: 22.5, chain: "base", note: "pizza night", count: 3, each: true } }, owe);
    expect(made?.params).toEqual({ amount: "22.5" });
    expect(made?.label).toBe("Request $22.50 · NEAR Intents");
    // The launch video's bill: four of us, $22.50 each.
    expect(await ground({ tool: "near.request", params: { amount: 90, count: 4, us: true, note: "dinner" } }, "dinner was $90 for the four of us"))
      .toMatchObject({ label: "Request $22.50 each · NEAR Intents", params: { amount: "90", count: 4, us: true, note: "dinner" } });

    expect(await ground({ tool: "near.send", params: { to: "alice.near", amount: 5 } }, "send 5 usdc to alice.near")).not.toBeNull();
    expect(await ground({ tool: "near.send", params: { to: "alice.near", amount: 5 } }, "send 5 usdc to bob.near")).toBeNull();
    expect(await ground({ tool: "near.send", params: { to: "alice.near", amount: 50 } }, "send 5 usdc to alice.near")).toBeNull();
    expect((await ground({ tool: "near.send", params: { to: "bob.near", amount: 10, with: "sol", withChain: "solana" } },
      "pay bob.near 10 usdc"))?.params).toEqual({ to: "bob.near", amount: "10", coin: "USDC" });

    const swap = await ground({ tool: "near.swap", params: { sell: "usdc", buy: "sol", amount: 20, sellChain: "arbitrum", buyChain: "solana" } },
      "swap 20 usdc on base to sol");
    expect(swap?.params).toEqual({ sell: "USDC", buy: "SOL", amount: "20", buyChain: "solana" });
    expect(await ground({ tool: "near.swap", params: { sell: "usdc", buy: "zec", amount: 20 } }, "swap 20 usdc to sol")).toBeNull();
    expect((await ground({ tool: "near.swap", params: { sell: "usdc", buy: "sol", amount: 25 } }, "swap 20 usdc to sol"))?.params)
      .toEqual({ sell: "USDC", buy: "SOL" });
  });

  it("finds numbers however they're written", async () => {
    const { numbersIn } = await import("../src/lib/actions.js");
    expect(numbersIn("$22.50 each, 1,200 total, 1.5k later, four of us, .5 btc")).toEqual([22.5, 1200, 1500, 0.5, 4]);
  });

  it("tells the prompt about them, and the stand-in finds them", () => {
    for (const tool of ["near.swap", "near.send", "near.request"]) expect(ACTION_GUIDE).toContain(tool);
    expect(mayAct("you owe me 22.50 for dinner")).toBe(true);
    expect(mockAction("you owe me 22.50 for dinner, I'm on solana")).toMatchObject({ tool: "near.request",
      label: "Request $22.50 on Solana · NEAR Intents" });
    expect(mockAction("swap 20 usdc on base to sol")?.label).toBe("Swap 20 USDC → SOL · NEAR Intents");
    expect(mockAction("send 5 usdc to alice.near")?.label).toBe("Send 5 USDC to alice.near · NEAR Intents");
    expect(mockAction("swap 20 usdc to eth")).toBeNull();
  });

  it("comes back from POST /suggest for a keyboard that knows NEAR's tools", async () => {
    const app = signedInApp();
    const res = (await app.inject({ method: "POST", url: "/suggest",
      payload: { text: "you owe me 22.50 for dinner, I'm on solana", deviceId: "actions-test-0002", actions: true, near: true } })).json();
    expect(res.action).toEqual({ tool: "near.request", label: "Request $22.50 on Solana · NEAR Intents",
      params: { amount: "22.5", chain: "solana", note: "dinner" } });
  });

  it("never reaches a keyboard from before NEAR's tools", async () => {
    const app = signedInApp();
    const res = (await app.inject({ method: "POST", url: "/suggest",
      payload: { text: "you owe me 22.50 for dinner, I'm on solana", deviceId: "actions-test-0003", actions: true } })).json();
    expect(res.ok).toBe(true);
    expect(res.action).toBeNull();
  });
});
