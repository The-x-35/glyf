import { getAddress, isAddress } from "viem";
import type { EvmChain, FetchFn } from "./evm.js";
import { findToken, resolveToken, tokensOn, wrappedNative, type EvmToken } from "./tokens.js";

/** Uniswap's own default token list (tokens.uniswap.org: free, no key), so
 *  any token Uniswap's app lists can be swapped by its symbol: "swap 0.1 eth
 *  to pepe on base". Fetched once and kept for six hours; a failed fetch
 *  keeps the last good copy (or none) and is tried again a minute later.
 *  The issuers' own addresses in tokens.ts always win over the list. */

export const TOKEN_LIST_URL = "https://tokens.uniswap.org";
const KEEP_MS = 6 * 60 * 60 * 1000;
const RETRY_MS = 60 * 1000;

export interface ListedToken extends EvmToken {
  logoURI?: string;
}

/** Shown first in the picker, in this order, when the chain has them. */
export const COMMON = ["ETH", "USDC", "USDT", "WETH", "DAI", "WBTC", "cbBTC", "UNI", "LINK", "ARB", "OP", "AAVE", "PEPE"];

interface Cache { at: number; byChain: Map<number, ListedToken[]>; tried: number }
let cache: Cache | null = null;
let inflight: Promise<Map<number, ListedToken[]>> | null = null;

/** For tests: forget the cached list. */
export function resetTokenList(): void {
  cache = null;
  inflight = null;
}

/** The list's tokens by chain id; empty when it can't be had. */
export async function tokenList(fetchImpl: FetchFn, now = Date.now()): Promise<Map<number, ListedToken[]>> {
  if (cache && now - cache.at < KEEP_MS) return cache.byChain;
  if (cache && now - cache.tried < RETRY_MS) return cache.byChain;
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const res = await fetchImpl(TOKEN_LIST_URL, { headers: { accept: "application/json" }, signal: AbortSignal.timeout(10_000) });
      if (!res.ok) throw new Error(`token list ${res.status}`);
      const json = await res.json() as { tokens?: { chainId: number; address: string; symbol: string; name: string; decimals: number; logoURI?: string }[] };
      const byChain = new Map<number, ListedToken[]>();
      for (const t of json.tokens ?? []) {
        if (!t || typeof t.chainId !== "number" || !isAddress(t.address ?? "", { strict: false })) continue;
        if (typeof t.symbol !== "string" || !Number.isInteger(t.decimals) || t.decimals < 0 || t.decimals > 36) continue;
        const row: ListedToken = { symbol: t.symbol.slice(0, 20), name: String(t.name ?? t.symbol).slice(0, 60),
          address: getAddress(t.address), decimals: t.decimals,
          ...(typeof t.logoURI === "string" && /^https:\/\//.test(t.logoURI) ? { logoURI: t.logoURI } : {}) };
        const list = byChain.get(t.chainId) ?? [];
        list.push(row);
        byChain.set(t.chainId, list);
      }
      cache = { at: now, tried: now, byChain };
      return byChain;
    } catch {
      cache = { at: cache?.at ?? 0, tried: now, byChain: cache?.byChain ?? new Map() };
      return cache.byChain;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}

/** Every token on `chain`: the issuers' list (gas coin first), then
 *  Uniswap's list with what the issuers' list already has left out. Logos
 *  come from Uniswap's list for both. */
export async function chainTokens(fetchImpl: FetchFn, chain: EvmChain): Promise<ListedToken[]> {
  const listed = (await tokenList(fetchImpl)).get(chain.id) ?? [];
  const byAddress = new Map(listed.map(t => [t.address.toLowerCase(), t]));
  const ethLogo = (await tokenList(fetchImpl)).get(1)?.find(t => t.symbol === "WETH")?.logoURI;
  const own: ListedToken[] = tokensOn(chain).map(t => {
    const logo = t.native ? ethLogo : byAddress.get(t.address.toLowerCase())?.logoURI;
    return { ...t, ...(logo ? { logoURI: logo } : {}) };
  });
  const ownAddresses = new Set(own.map(t => t.address.toLowerCase()));
  const ownSymbols = new Set(own.map(t => t.symbol.toUpperCase()));
  // A list token that shares a symbol with an issuer's token is a bridged
  // twin ("USDC" bridged on Arbitrum): kept, but after.
  const rest = listed.filter(t => !ownAddresses.has(t.address.toLowerCase()));
  rest.sort((a, b) => Number(ownSymbols.has(a.symbol.toUpperCase())) - Number(ownSymbols.has(b.symbol.toUpperCase())));
  return [...own, ...rest];
}

function commonRank(t: ListedToken): number {
  const i = COMMON.findIndex(s => s.toUpperCase() === t.symbol.toUpperCase());
  return i < 0 ? COMMON.length : i;
}

/** The picker's rows: with no query the common tokens first, then the
 *  rest; with a query, an exact symbol, then symbols that start with it,
 *  then names that contain it. At most `limit`. */
export function searchTokens(all: ListedToken[], query: string, limit = 40): ListedToken[] {
  const q = query.trim().replace(/^\$/, "").toLowerCase();
  if (!q) {
    const seen = new Set<string>();
    const common = all.filter(t => commonRank(t) < COMMON.length)
      .filter(t => { const k = t.symbol.toUpperCase(); if (seen.has(k)) return false; seen.add(k); return true; })
      .sort((a, b) => commonRank(a) - commonRank(b));
    const commonSet = new Set(common);
    return [...common, ...all.filter(t => !commonSet.has(t))].slice(0, limit);
  }
  if (isAddress(q, { strict: false })) return all.filter(t => t.address.toLowerCase() === q).slice(0, limit);
  const score = (t: ListedToken): number => {
    const s = t.symbol.toLowerCase();
    if (s === q) return 0;
    if (s.startsWith(q)) return 1;
    if (t.name.toLowerCase().startsWith(q)) return 2;
    if (s.includes(q) || t.name.toLowerCase().includes(q)) return 3;
    return -1;
  };
  return all.map((t, i) => ({ t, s: score(t), i }))
    .filter(x => x.s >= 0)
    .sort((a, b) => a.s - b.s || commonRank(a.t) - commonRank(b.t) || a.i - b.i)
    .slice(0, limit)
    .map(x => x.t);
}

/** A symbol Uniswap's list knows on `chain` (the first listed wins). */
export async function listedBySymbol(fetchImpl: FetchFn, chain: EvmChain, symbol: string): Promise<ListedToken | null> {
  const want = symbol.trim().replace(/^\$/, "").toUpperCase();
  if (!want) return null;
  const list = (await tokenList(fetchImpl)).get(chain.id) ?? [];
  return list.find(t => t.symbol.toUpperCase() === want) ?? null;
}

/** A token by symbol or address on `chain`: the issuers' list, then
 *  Uniswap's list, then (for a pasted address) what the contract says. */
export async function resolveAnyToken(fetchImpl: FetchFn, chain: EvmChain, query: string): Promise<EvmToken | null> {
  const own = findToken(chain, query);
  if (own) return own;
  if (isAddress(query.trim(), { strict: false })) {
    const listed = ((await tokenList(fetchImpl)).get(chain.id) ?? []).find(t => t.address.toLowerCase() === query.trim().toLowerCase());
    if (listed) return { symbol: listed.symbol, name: listed.name, address: listed.address, decimals: listed.decimals };
    return resolveToken(fetchImpl, chain, query);
  }
  const listed = await listedBySymbol(fetchImpl, chain, query);
  return listed ? { symbol: listed.symbol, name: listed.name, address: listed.address, decimals: listed.decimals } : null;
}

/** The tokens a two-pool route may pass through on `chain`: WETH, USDC. */
export function routeMids(chain: EvmChain): `0x${string}`[] {
  const mids: `0x${string}`[] = [];
  const weth = wrappedNative(chain);
  if (weth) mids.push(weth.address);
  const usdc = findToken(chain, "USDC");
  if (usdc) mids.push(usdc.address);
  return mids;
}
