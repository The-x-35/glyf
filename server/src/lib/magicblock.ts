/**
 * MagicBlock's Private Payments API — the thing behind "Private sends by
 * MagicBlock" on the website, now real.
 *
 * It builds UNSIGNED Solana transactions: a private transfer goes out through
 * a private ephemeral rollup so the link between sender, amount and recipient
 * is not left on chain, and comes back to Solana at settlement. Glyf never
 * holds a key — the API returns base64, the app signs it with the user's
 * Privy wallet, and the signed bytes go straight to Solana.
 *
 * Docs: https://docs.magicblock.gg/pages/ephemeral-spl-token/api-reference
 */

const BASE = process.env.MAGICBLOCK_API_BASE?.replace(/\/+$/, "")
  ?? "https://payments.magicblock.app";

/** Well-known mints, so callers can say "USDC" instead of a base58 string. */
export const MINTS: Record<string, { mint: string; decimals: number }> = {
  USDC: { mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6 },
  USDT: { mint: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", decimals: 6 },
};

export interface BuiltTransaction {
  kind: string;
  version: "legacy" | "v0";
  transactionBase64: string;
  sendTo: "base" | "ephemeral";
  from: "base" | "ephemeral";
  recentBlockhash: string;
  lastValidBlockHeight: number;
  requiredSigners: string[];
  fees?: { lamports?: string; tokens?: string };
}

export interface TransferRequest {
  from: string;
  to: string;
  /** Mint address, or a key of MINTS. */
  mint: string;
  /** Whole tokens, as typed ("12.5"). Converted with the mint's decimals. */
  amount: string;
  private?: boolean;
  cluster?: "mainnet" | "devnet";
  memo?: string;
}

export class MagicBlockError extends Error {
  constructor(message: string, readonly code: string, readonly status: number) {
    super(message);
  }
}

function resolveMint(mint: string): { mint: string; decimals: number } {
  const known = MINTS[mint.toUpperCase()];
  if (known) return known;
  return { mint, decimals: 6 };
}

/** "12.5" + 6 decimals → 12500000, without floating point. */
export function baseUnits(amount: string, decimals: number): bigint {
  const trimmed = amount.trim().replace(/,/g, "");
  if (!/^\d*(\.\d*)?$/.test(trimmed) || trimmed === "" || trimmed === ".") {
    throw new MagicBlockError("Amount must be a number", "BAD_AMOUNT", 400);
  }
  const [whole, frac = ""] = trimmed.split(".");
  const padded = (frac + "0".repeat(decimals)).slice(0, decimals);
  const units = BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(padded || "0");
  if (units <= 0n) throw new MagicBlockError("Amount must be above zero", "BAD_AMOUNT", 400);
  return units;
}

async function post(path: string, body: unknown, token?: string): Promise<unknown> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(12_000),
  });
  const json = await res.json().catch(() => ({})) as
    { error?: { code?: string; message?: string } };
  if (!res.ok || json.error) {
    throw new MagicBlockError(
      json.error?.message ?? `MagicBlock error ${res.status}`,
      json.error?.code ?? "UPSTREAM",
      res.status === 400 ? 400 : 502);
  }
  return json;
}

/** Builds the unsigned transfer. Private by default: that is the point. */
export async function buildTransfer(req: TransferRequest): Promise<BuiltTransaction> {
  const { mint, decimals } = resolveMint(req.mint);
  const body: Record<string, unknown> = {
    from: req.from,
    to: req.to,
    mint,
    amount: Number(baseUnits(req.amount, decimals)),
    visibility: req.private === false ? "public" : "private",
    initAtasIfMissing: true,
  };
  if (req.cluster) body.cluster = req.cluster;
  if (req.memo) body.memo = req.memo.slice(0, 120);
  return await post("/v1/spl/transfer", body) as BuiltTransaction;
}

/** Public SPL balance on the base chain. */
export async function balance(owner: string, mintKey = "USDC",
                              cluster?: string): Promise<{ amount: string; decimals: number }> {
  const { mint, decimals } = resolveMint(mintKey);
  const url = new URL(`${BASE}/v1/spl/balance`);
  url.searchParams.set("owner", owner);
  url.searchParams.set("mint", mint);
  if (cluster) url.searchParams.set("cluster", cluster);
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  const json = await res.json().catch(() => ({})) as
    { amount?: string; uiAmount?: number; error?: { message?: string; code?: string } };
  if (!res.ok || json.error) {
    throw new MagicBlockError(json.error?.message ?? "Balance unavailable",
                              json.error?.code ?? "UPSTREAM", 502);
  }
  return { amount: String(json.amount ?? json.uiAmount ?? "0"), decimals };
}

/** A swap quote between two mints (the Swap tab). */
export async function quote(from: string, to: string, amount: string,
                            cluster?: string): Promise<unknown> {
  const a = resolveMint(from), b = resolveMint(to);
  const body: Record<string, unknown> = {
    inputMint: a.mint, outputMint: b.mint,
    amount: Number(baseUnits(amount, a.decimals)),
  };
  if (cluster) body.cluster = cluster;
  return await post("/v1/spl/quote", body);
}
