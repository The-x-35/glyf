import { formatUnits } from "viem";
import type { FetchFn } from "./evm.js";
import { addressFits, IntentsError, NEAR_CHAINS, nearChainOf, type NearChain, type NearIntents, type QuoteAnswer } from "./nearintents.js";

/**
 * Earn (docs/NEAR-SPEC.md, "Earn"): "put $50 to work" parks idle USDC or SOL
 * in a yield vault through NEAR Intents 1Click Earn
 * (https://docs.near-intents.org/integration/distribution-channels/1click-api/earn).
 *
 * Earn is no separate API: a deposit is an ordinary 1Click quote whose
 * destination is the vault's receipt token (its shares), and "take it out"
 * is the reverse quote, shares to the coin. So the answer is /near/quote's
 * very shape, deposit and all, and the app's NearFlow pays it unchanged.
 *
 * 1Click returns no APY. Each vault's rate comes from its own protocol's
 * public, keyless API (Morpho's GraphQL, Kamino's REST), kept ten minutes;
 * when that API doesn't answer, the rate is left out rather than guessed.
 */

export type ApySource =
  | { kind: "morpho"; address: string; chainId: number }
  | { kind: "kamino"; vault: string };

export interface EarnVault {
  /** Glyf's id for the vault, what the phone sends back. */
  id: string;
  name: string;
  protocol: string;
  /** Glyf chain key where the shares live. */
  chain: string;
  /** 1Click's asset id of the receipt token (the shares). */
  assetId: string;
  receipt: string;
  /** The coin the vault holds and pays back. */
  underlying: string;
  apySource: ApySource | null;
  /** The vault's own page. */
  url: string | null;
  /** What the receipt token is, in a line (1Click wraps some vaults). */
  about: string;
}

/**
 * 1Click Earn's listings that fit Glyf: their shares land on a chain the
 * phone's wallets hold (MetaMask on EVM, Phantom on Solana). Checked live on
 * 2026-11-13: each one quoted both ways, and the wrapper contracts were
 * read on chain (name(), asset()). A vault 1Click stops listing drops out
 * of GET /near/earn/vaults by itself.
 *
 * Steakhouse USDC (steakUSDC on Ethereum) is listed too but answered "No
 * liquidity available" to every quote, so it isn't offered.
 */
export const EARN_VAULTS: readonly EarnVault[] = [
  {
    id: "gtusdcp", name: "Gauntlet USDC Prime", protocol: "Morpho", chain: "base",
    assetId: "nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near", receipt: "gtUSDCp", underlying: "USDC",
    // 1Click's token (0x0bb6…) is "NEAR Gauntlet USDC Prime", an ERC-4626
    // whose asset() is Morpho's vault 0xeE8F…4b61: the yield is that vault's.
    apySource: { kind: "morpho", address: "0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61", chainId: 8453 },
    url: "https://app.morpho.org/base/vault/0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61/gauntlet-usdc-prime",
    about: "Shares of Morpho's Gauntlet USDC Prime vault on Base",
  },
  {
    id: "kamino-sol", name: "Kamino SOL Balanced", protocol: "Kamino", chain: "solana",
    assetId: "nep141:sol-0xa69aa1bcb03a369e338156a8718ad60271145803.omdep.near", receipt: "kV-gtSOLb", underlying: "SOL",
    // The shares mint 5EBs…dBK is Kamino vault DcCR…khpg's sharesMint.
    apySource: { kind: "kamino", vault: "DcCRSdUMgAt6ZMeuL4BJAsZmJgND2LQd74Zq4z6ckhpg" },
    url: "https://kamino.com/earn/lend/DcCRSdUMgAt6ZMeuL4BJAsZmJgND2LQd74Zq4z6ckhpg",
    about: "Shares of Kamino's SOL Balanced vault on Solana",
  },
  {
    id: "taler-usdc", name: "Taler USDC", protocol: "Taler", chain: "ethereum",
    assetId: "nep141:eth-0x0f38f1ce62776d4a0038bc6cac66877a5687383b.omft.near", receipt: "TLO", underlying: "USDC",
    // No public rate API found for "TAU Lending Optimizer" (0x0f38…383b).
    apySource: null, url: null,
    about: "Shares of Taler's USDC lending optimizer on Ethereum",
  },
];

/** Where each coin earns when no vault is named. */
const DEFAULT_VAULT: Record<string, string> = { USDC: "gtusdcp", SOL: "kamino-sol" };

export const MORPHO_API = "https://blue-api.morpho.org/graphql";
export const KAMINO_API = "https://api.kamino.finance";
const APY_KEEP_MS = 10 * 60 * 1000;

export interface Apy {
  /** Percent a year, to two places (4.5 is 4.5%). */
  apy: number;
  /** What the number is, in the protocol's terms. */
  basis: string;
  source: string;
  at: string;
}

/** A vault by Glyf id, receipt symbol, 1Click asset id, or protocol word. */
export function vaultOf(word: unknown): EarnVault | null {
  if (typeof word !== "string" || !word.trim()) return null;
  const w = word.trim().toLowerCase();
  return EARN_VAULTS.find(v => v.id === w || v.receipt.toLowerCase() === w || v.assetId.toLowerCase() === w)
    ?? EARN_VAULTS.find(v => v.protocol.toLowerCase() === w)
    ?? null;
}

/** The vault a coin goes into when none was named. */
export function defaultVault(coin: string): EarnVault | null {
  const id = DEFAULT_VAULT[coin.trim().replace(/^\$/, "").toUpperCase()];
  return id ? vaultOf(id) : null;
}

const pct = (fraction: number) => Math.round(fraction * 10000) / 100;

export class EarnRates {
  private kept = new Map<string, { at: number; apy: Apy | null }>();
  private readonly fetchImpl: FetchFn;
  private readonly now: () => number;

  constructor(deps: { fetchImpl?: FetchFn; now?: () => number } = {}) {
    this.fetchImpl = deps.fetchImpl ?? fetch;
    this.now = deps.now ?? Date.now;
  }

  /** The vault's APY from its own protocol, or null when that can't be
   *  read (no API, no answer, or an answer that isn't a sane number). */
  async apy(vault: EarnVault): Promise<Apy | null> {
    if (!vault.apySource) return null;
    const hit = this.kept.get(vault.id);
    const t = this.now();
    if (hit && t - hit.at < APY_KEEP_MS) return hit.apy;
    let apy: Apy | null = null;
    try {
      apy = vault.apySource.kind === "morpho" ? await this.morpho(vault.apySource) : await this.kamino(vault.apySource);
    } catch {
      apy = null;
    }
    // A miss is kept a minute, so a dead API isn't asked on every look.
    this.kept.set(vault.id, { at: apy ? t : t - APY_KEEP_MS + 60_000, apy });
    return apy;
  }

  private async morpho(src: Extract<ApySource, { kind: "morpho" }>): Promise<Apy | null> {
    const res = await this.fetchImpl(MORPHO_API, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        query: "query($a:String!,$c:Int!){vaultByAddress(address:$a,chainId:$c){name state{netApy apy}}}",
        variables: { a: src.address, c: src.chainId },
      }),
      signal: AbortSignal.timeout(5_000),
    });
    const json = await res.json().catch(() => null) as any;
    const net = json?.data?.vaultByAddress?.state?.netApy;
    if (!res.ok || typeof net !== "number" || !Number.isFinite(net) || net < 0 || net > 1) return null;
    return { apy: pct(net), basis: "net APY after the vault's fees", source: "Morpho", at: new Date(this.now()).toISOString() };
  }

  private async kamino(src: Extract<ApySource, { kind: "kamino" }>): Promise<Apy | null> {
    const res = await this.fetchImpl(`${KAMINO_API}/kvaults/vaults/${src.vault}/metrics`, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(5_000),
    });
    const json = await res.json().catch(() => null) as any;
    const apy = Number(json?.apy);
    if (!res.ok || json?.apy === undefined || !Number.isFinite(apy) || apy < 0 || apy > 1) return null;
    return { apy: pct(apy), basis: "current APY", source: "Kamino", at: new Date(this.now()).toISOString() };
  }
}

export interface VaultRow {
  id: string;
  name: string;
  protocol: string;
  chain: string;
  chainName: string;
  receipt: string;
  assetId: string;
  underlying: string;
  apy: number | null;
  apyBasis: string | null;
  apySource: string | null;
  url: string | null;
  about: string;
  /** The coin the vault takes by default: deposit this on `chain` for the
   *  cheapest route (any 1Click coin on any chain is accepted). */
  default: boolean;
}

/** Glyf's vaults that 1Click lists right now, each with its APY if known. */
export async function earnVaults(intents: NearIntents, rates: EarnRates): Promise<VaultRow[]> {
  const listed = new Set((await intents.tokens()).map(t => t.assetId));
  const live = EARN_VAULTS.filter(v => listed.has(v.assetId));
  const apys = await Promise.all(live.map(v => rates.apy(v)));
  return live.map((v, i) => ({
    id: v.id, name: v.name, protocol: v.protocol, chain: v.chain, chainName: NEAR_CHAINS[v.chain].name,
    receipt: v.receipt, assetId: v.assetId, underlying: v.underlying,
    apy: apys[i]?.apy ?? null, apyBasis: apys[i]?.basis ?? null, apySource: apys[i]?.source ?? null,
    url: v.url, about: v.about, default: DEFAULT_VAULT[v.underlying] === v.id,
  }));
}

export interface EarnInput {
  direction: "in" | "out";
  /** What's paid in (in) or paid back (out): USDC, SOL… */
  coin: string;
  /** Where that coin is (in) or should land (out). Unsaid: the vault's own
   *  chain for its own coin, else the coin's home or Base. */
  chain?: string;
  /** Whole coins: what goes in, or what comes back out (exact). */
  amount?: string;
  /** Out only: the shares to redeem, in base units ("everything": the app
   *  reads its share balance and sends it). */
  shares?: string;
  vault?: string;
  refundTo?: string;
  recipient?: string;
  slippage?: number;
}

export interface EarnAnswer extends QuoteAnswer {
  kind: "earn";
  direction: "in" | "out";
  vault: VaultRow;
  /** One line for the panel: "≈ $19.90 in Gauntlet USDC Prime". */
  words: string;
}

function chainFor(input: EarnInput, vault: EarnVault): NearChain {
  if (input.chain) {
    const c = nearChainOf(input.chain);
    if (!c) throw new IntentsError(400, `NEAR Intents isn't on ${input.chain.slice(0, 20)}`);
    return c;
  }
  const coin = input.coin.trim().replace(/^\$/, "").toUpperCase();
  if (coin === vault.underlying) return NEAR_CHAINS[vault.chain];
  return coin === "SOL" ? NEAR_CHAINS.solana : NEAR_CHAINS.base;
}

const money = (usd: string | null) => (usd === null ? null : `$${Number(usd).toFixed(2)}`);

/** A deposit into a vault, or a withdrawal out of it, as a 1Click quote. */
export async function earnQuote(intents: NearIntents, rates: EarnRates, input: EarnInput): Promise<EarnAnswer> {
  const coin = input.coin.trim().replace(/^\$/, "").toUpperCase();
  const vault = input.vault ? vaultOf(input.vault) : defaultVault(coin);
  if (!vault) {
    throw new IntentsError(400, input.vault ? "Glyf doesn't know that vault" : `Earn takes USDC or SOL, not ${coin.slice(0, 12)}`);
  }
  const other = chainFor(input, vault);
  const vaultChain = NEAR_CHAINS[vault.chain];
  const out = input.direction === "out";
  // Where the shares land (in) or where the payout lands (out) has to be an
  // address on that chain (the refund address is checked by the quote).
  const getChain = out ? other : vaultChain;
  if (input.recipient && !addressFits(getChain, input.recipient)) {
    throw new IntentsError(400, out ? `The payout needs your ${getChain.name} address` : `${vault.name}'s shares need your ${getChain.name} address`);
  }
  let amount = input.amount;
  let exact: "in" | "out" = "in";
  if (out) {
    if (input.shares) {
      if (!/^\d{1,60}$/.test(input.shares) || BigInt(input.shares) <= 0n) throw new IntentsError(400, "shares?");
      const receipt = await intents.token(vaultChain, vault.assetId);
      amount = formatUnits(BigInt(input.shares), receipt.decimals);
    } else {
      // "Take 20 USDC out": exactly 20 back, the shares it takes go in.
      exact = "out";
    }
  }
  if (!amount) throw new IntentsError(400, "amount?");
  const sides = out
    ? { sell: vault.assetId, sellChain: vault.chain, buy: coin, buyChain: other.key }
    : { sell: coin, sellChain: other.key, buy: vault.assetId, buyChain: vault.chain };
  let quote: QuoteAnswer;
  try {
    quote = await intents.quote({ ...sides, amount, exact, refundTo: input.refundTo, recipient: input.recipient,
      slippage: input.slippage });
  } catch (err) {
    if (err instanceof IntentsError && err.status === 400 && /liquidity/i.test(err.message)) {
      throw new IntentsError(400, out ? `NEAR Intents can't take that out of ${vault.name} right now`
        : `NEAR Intents can't put that into ${vault.name} right now`);
    }
    if (err instanceof IntentsError && err.status === 400 && /same coin/i.test(err.message)) {
      throw new IntentsError(400, "Pick a coin to put in, not the vault's own shares");
    }
    throw err;
  }
  const apy = await rates.apy(vault);
  const row: VaultRow = {
    id: vault.id, name: vault.name, protocol: vault.protocol, chain: vault.chain, chainName: vaultChain.name,
    receipt: vault.receipt, assetId: vault.assetId, underlying: vault.underlying,
    apy: apy?.apy ?? null, apyBasis: apy?.basis ?? null, apySource: apy?.source ?? null,
    url: vault.url, about: vault.about, default: DEFAULT_VAULT[vault.underlying] === vault.id,
  };
  const words = out
    ? `${quote.amountOut} ${quote.buy.symbol} back on ${NEAR_CHAINS[quote.buy.chain].name} from ${vault.name}`
    : `${money(quote.amountOutUsd) ?? `${quote.amountOut} ${vault.receipt}`} in ${vault.name}${row.apy !== null ? ` at ${row.apy}% APY` : ""}`;
  return { ...quote, kind: "earn", direction: out ? "out" : "in", vault: row, words: out ? words : `≈ ${words}` };
}
