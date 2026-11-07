// Glyf's in-keyboard signer (ETHGlobal demo, Arpit 2026-11-07: "Everything
// should happen inside the keyboard"). Runs in JavaScriptCore: the keyboard
// supplies __native.post(path, json, id) for Glyf's API and __native.timer(ms, id);
// this file builds, signs and sends the trade with the Glyf wallet's key.
import { mnemonicToAccount } from "viem/accounts";
import { base, mainnet, arbitrum, optimism } from "viem/chains";

const CHAINS = { base, ethereum: mainnet, arbitrum, optimism };
const pending = new Map();
let seq = 0;
globalThis.__resolve = (id, ok, json) => {
  const p = pending.get(id); if (!p) return; pending.delete(id);
  ok ? p.resolve(json ? JSON.parse(json) : null) : p.reject(new Error(json || "network"));
};
globalThis.setTimeout = globalThis.setTimeout || ((fn, ms) => { const id = ++seq; pending.set(id, { resolve: fn, reject: () => {} }); __native.timer(ms || 0, id); return id; });
globalThis.clearTimeout = globalThis.clearTimeout || ((id) => pending.delete(id));
function api(path, body) {
  return new Promise((resolve, reject) => {
    const id = ++seq; pending.set(id, { resolve, reject });
    __native.post(path, body === undefined ? "" : JSON.stringify(body), id);
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const say = (step) => __native.step(step);

function clients(phrase, chainName) {
  const chain = CHAINS[chainName] ?? base;
  const account = mnemonicToAccount(phrase);
  const rpc = async (method, params = []) => {
    const r = await api("/evm/rpc", { chain: chainName, method, params });
    if (!r || r.ok === false) throw new Error((r && r.error) || method + " failed");
    return r.result;
  };
  return { account, chain, rpc };
}

const hex = (n) => "0x" + BigInt(n).toString(16);

/** One transaction: nonce, gas and fees asked of the node (only the calls
 *  Glyf's /evm/rpc allows), signed here, sent, and waited for. */
async function sendTx(c, tx) {
  const from = c.account.address;
  const value = BigInt(tx.value ?? "0");
  const data = tx.data ?? "0x";
  const nonce = Number(BigInt(await c.rpc("eth_getTransactionCount", [from, "pending"])));
  const gas = tx.gas ? BigInt(tx.gas)
    : (BigInt(await c.rpc("eth_estimateGas", [{ from, to: tx.to, data, value: hex(value) }])) * 12n) / 10n;
  const gasPrice = BigInt(await c.rpc("eth_gasPrice"));
  let tip = 1000000n;
  try { tip = BigInt(await c.rpc("eth_maxPriorityFeePerGas")); } catch {}
  const maxFeePerGas = gasPrice * 2n + tip;
  const raw = await c.account.signTransaction({ chainId: c.chain.id, type: "eip1559", to: tx.to, data, value,
    nonce, gas, maxFeePerGas, maxPriorityFeePerGas: tip });
  const hash = await c.rpc("eth_sendRawTransaction", [raw]);
  for (let i = 0; i < 60; i++) {
    await sleep(1500);
    const receipt = await c.rpc("eth_getTransactionReceipt", [hash]).catch(() => null);
    if (receipt) {
      if (receipt.status !== "0x1") throw new Error("The transaction reverted");
      return hash;
    }
  }
  return hash;
}

const STABLE = new Set(["USDC", "USDT", "DAI"]);
const FLASH_TYPES = { limit: "limit", stop: "stop", stopLoss: "stop-loss", takeProfit: "take-profit",
  bracket: "bracket", trailingStop: "trailing-stop", twap: "twap", "stop-loss": "stop-loss", "take-profit": "take-profit", "trailing-stop": "trailing-stop" };
const trim = (n) => String(Number(n.toPrecision(12)));

async function swap(q, c) {
  say("Asking Uniswap…");
  const body = { chain: q.chain, sell: q.sellAddress ?? q.sell, buy: q.buyAddress ?? q.buy,
    recipient: c.account.address, swapper: c.account.address, slippage: 0.5 };
  if (q.buyAmount) {
    const cost = await api("/uniswap/quote", { chain: q.chain, sell: q.buyAddress ?? q.buy, buy: q.sellAddress ?? q.sell, amount: q.buyAmount });
    body.amount = trim(Number(cost.amountOut) * 1.006);
  } else body.amount = q.amount;
  if (!body.amount) throw new Error("Say how much to swap");
  const s = await api("/uniswap/swap", body);
  if (!s || s.ok === false) throw new Error(s?.error || "Uniswap had no route");
  if (s.approvalReset) { say("Resetting the allowance…"); await sendTx(c, s.approvalReset); }
  if (s.approval) { say("Approving " + q.sell + "…"); await sendTx(c, s.approval); }
  let hash = null;
  for (const tx of s.txs ?? []) { say("Swapping…"); hash = await sendTx(c, tx); }
  return { hash, amountOut: s.amountOut, url: hash ? explorer(q.chain) + hash : null };
}

function explorer(chain) {
  return { base: "https://basescan.org/tx/", ethereum: "https://etherscan.io/tx/", arbitrum: "https://arbiscan.io/tx/",
    optimism: "https://optimistic.etherscan.io/tx/" }[chain] ?? "https://basescan.org/tx/";
}

function typedOf(raw) {
  // Flash sends its typed data as a JSON string.
  const t = typeof raw === "string" ? JSON.parse(raw) : raw;
  const types = { ...t.types }; delete types.EIP712Domain;
  // Flash writes domain.chainId as a string, and viem leaves a string chainId
  // out of the domain hash, so the signature fails Flash's check. A number
  // (as Definitive's own flash-mcp does).
  const domain = { ...t.domain };
  if (domain.chainId !== undefined && domain.chainId !== null) domain.chainId = Number(domain.chainId);
  return { domain, types, primaryType: t.primaryType, message: t.message };
}

async function flash(q, kind, c) {
  say("Asking Flash…");
  const sell = q.sell, buy = q.buy;
  const buying = STABLE.has(sell) && !STABLE.has(buy);
  const target = buying ? buy : sell, contra = buying ? sell : buy;
  const body = { targetChain: q.chain, contraChain: q.chain,
    target: (buying ? q.buyAddress : q.sellAddress) ?? target, contra: (buying ? q.sellAddress : q.buyAddress) ?? contra,
    side: buying ? "buy" : "sell", orderType: FLASH_TYPES[kind] ?? "market", funderAddress: c.account.address };
  let qty = q.amount;
  if (buying && q.buyAmount && q.price && kind !== "bracket") qty = trim(Number(q.buyAmount) * Number(q.price));
  if (!qty) throw new Error("Say how much");
  body.qty = qty;
  const price = q.price;
  if (kind === "limit") body.limitNotionalPrice = price;
  if (kind === "stop") body.triggers = [{ notionalPrice: price, triggerType: "upper" }];
  if (kind === "stopLoss" || kind === "stop-loss") body.triggers = [{ notionalPrice: price, triggerType: "lower" }];
  if (kind === "takeProfit" || kind === "take-profit") body.triggers = [{ notionalPrice: price, triggerType: "upper" }];
  if (kind === "bracket") {
    if (buying) { body.orderType = "market"; body.attachedBracket = { takeProfit: { notionalPrice: price }, stopLoss: { notionalPrice: q.stopPrice } }; }
    else body.triggers = [{ notionalPrice: price, triggerType: "upper" }, { notionalPrice: q.stopPrice, triggerType: "lower" }];
  }
  if (kind === "trailingStop" || kind === "trailing-stop") body.trailingStop = { trailPercent: trim(Number(q.trail ?? "5") / 100) };
  if (kind === "twap") body.durationSeconds = Number(q.duration) || 86400;
  const quote = await api("/flash/quote", body);
  if (!quote || quote.ok === false) throw new Error(quote?.error || "Flash had no quote");
  const evm = quote.evm ?? {};
  const setup = [evm.approveTx ?? evm.approvalTx, ...(evm.setupTxs ?? quote.setupTxs ?? []),
    (sell === "ETH" ? quote.wrap?.evmTx : null)].filter((t) => t && t.to);
  for (const tx of setup) { say("Approving for Flash…"); await sendTx(c, tx); }
  const order = { ...(quote.order ?? {}) };
  const typed = order.evmOrderTypedData ?? evm.orderTypedData;
  if (!typed) throw new Error(quote.error || "Flash sent nothing to sign");
  order.evmOrderTypedData = typeof typed === "string" ? typed : JSON.stringify(typed);
  say("Signing the order…");
  order.userSignature = await c.account.signTypedData(typedOf(typed));
  const permit = order.evmPermitTypedData ?? evm.permitTypedData;
  if (permit) {
    order.evmPermitTypedData = typeof permit === "string" ? permit : JSON.stringify(permit);
    order.evmPermitSignature = await c.account.signTypedData(typedOf(permit));
  }
  const pairTyped = quote.attachedBracket?.evm?.orderTypedData;
  if (order.attachedBracket && pairTyped) {
    const pair = { ...order.attachedBracket };
    pair.userSignature = await c.account.signTypedData(typedOf(pairTyped));
    const pairPermit = pair.evmPermitTypedData ?? quote.attachedBracket?.evm?.permitTypedData;
    if (pairPermit) {
      pair.evmPermitTypedData = typeof pairPermit === "string" ? pairPermit : JSON.stringify(pairPermit);
      pair.evmPermitSignature = await c.account.signTypedData(typedOf(pairPermit));
    }
    order.attachedBracket = pair;
  }
  say("Placing the order…");
  const placed = await api("/flash/order", order);
  const id = placed?.orderId ?? placed?.id;
  if (!id) throw new Error(placed?.error || "Flash didn't take the order");
  return { orderId: String(id), url: "https://app.definitive.fi/orders/" + id };
}

globalThis.GlyfSigner = {
  address(phrase) { return mnemonicToAccount(phrase).address; },
  async selfTest(phrase, typedJSON) {
    try {
      const a = mnemonicToAccount(phrase);
      const sig = await a.signTypedData(typedOf(JSON.parse(typedJSON)));
      const raw = await a.signTransaction({ chainId: 8453, type: "eip1559", to: a.address, value: 1n, nonce: 0, gas: 21000n, maxFeePerGas: 1000000000n, maxPriorityFeePerGas: 1000000n });
      __native.done(JSON.stringify({ ok: true, sig, raw: raw.slice(0, 20) }));
    } catch (e) { __native.done(JSON.stringify({ ok: false, error: String(e && e.message || e) })); }
  },
  async run(phrase, qJSON) {
    try {
      const q = JSON.parse(qJSON);
      const kind = q.kind ?? "swap";
      const c = clients(phrase, q.chain ?? "base");
      const out = kind === "swap" ? await swap(q, c) : await flash(q, kind, c);
      __native.done(JSON.stringify({ ok: true, ...out }));
    } catch (e) {
      __native.done(JSON.stringify({ ok: false, error: String(e && (e.shortMessage || e.message) || e) }));
    }
  },
};
