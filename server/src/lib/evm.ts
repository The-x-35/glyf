/** The EVM chains the app's Ethereum wallet can use, and the one way this
 *  server talks to their nodes.
 *
 *  Every chain has a free public RPC (PublicNode for the big ones, each
 *  chain's own for the testnets), so nothing here needs a key. Each one can
 *  be pointed somewhere else with its own variable (ETH_RPC_URL,
 *  BASE_RPC_URL…) once a keyed node is worth it. The wallet itself lives on
 *  the phone: it builds and signs every transaction, and the server only
 *  carries calls to a node and back. */

export interface EvmChain {
  /** What the app and the keyboard say: "base", "arbitrum". */
  key: string;
  id: number;
  name: string;
  /** The gas coin's ticker. */
  native: string;
  /** Free public RPC, used when `env` isn't set. */
  rpc: string;
  env: string;
  testnet?: boolean;
}

/** Chain ids and RPCs checked with eth_chainId on 2026-11-06. */
export const EVM_CHAINS: Record<string, EvmChain> = {
  ethereum: { key: "ethereum", id: 1, name: "Ethereum", native: "ETH",
    rpc: "https://ethereum-rpc.publicnode.com", env: "ETH_RPC_URL" },
  base: { key: "base", id: 8453, name: "Base", native: "ETH",
    rpc: "https://base-rpc.publicnode.com", env: "BASE_RPC_URL" },
  arbitrum: { key: "arbitrum", id: 42161, name: "Arbitrum", native: "ETH",
    rpc: "https://arbitrum-one-rpc.publicnode.com", env: "ARBITRUM_RPC_URL" },
  optimism: { key: "optimism", id: 10, name: "OP Mainnet", native: "ETH",
    rpc: "https://optimism-rpc.publicnode.com", env: "OPTIMISM_RPC_URL" },
  unichain: { key: "unichain", id: 130, name: "Unichain", native: "ETH",
    rpc: "https://unichain-rpc.publicnode.com", env: "UNICHAIN_RPC_URL" },
  "base-sepolia": { key: "base-sepolia", id: 84532, name: "Base Sepolia", native: "ETH",
    rpc: "https://base-sepolia-rpc.publicnode.com", env: "BASE_SEPOLIA_RPC_URL", testnet: true },
  sepolia: { key: "sepolia", id: 11155111, name: "Sepolia", native: "ETH",
    rpc: "https://ethereum-sepolia-rpc.publicnode.com", env: "SEPOLIA_RPC_URL", testnet: true },
};

/** What people type for a chain ("eth", "arb", "op", "mainnet"). */
const ALIASES: Record<string, string> = {
  eth: "ethereum", mainnet: "ethereum", "ethereum-mainnet": "ethereum",
  arb: "arbitrum", "arbitrum-one": "arbitrum",
  op: "optimism", "op-mainnet": "optimism",
  "base-testnet": "base-sepolia",
  "ethereum-sepolia": "sepolia",
};

/** A chain by its key, a nickname or its id ("base", "Base", 8453, "8453"). */
export function chainOf(input: unknown): EvmChain | null {
  if (typeof input === "number" || (typeof input === "string" && /^\d+$/.test(input.trim()))) {
    const id = Number(input);
    return Object.values(EVM_CHAINS).find(c => c.id === id) ?? null;
  }
  if (typeof input !== "string") return null;
  const key = input.trim().toLowerCase().replace(/[\s_]+/g, "-");
  return EVM_CHAINS[key] ?? EVM_CHAINS[ALIASES[key] ?? ""] ?? null;
}

export function rpcUrlOf(chain: EvmChain): string {
  return (process.env[chain.env] ?? "").trim() || chain.rpc;
}

/** The node's own error ("insufficient funds for gas"…), kept apart from
 *  "the node didn't answer" so a route can tell the person which it was. */
export class RpcError extends Error {
  constructor(message: string, readonly code?: number, readonly data?: unknown) {
    super(message);
  }
}

export type FetchFn = typeof fetch;

/** One JSON-RPC call. Throws RpcError for the node's error, anything else
 *  when the node can't be reached. */
export async function evmRpc(fetchImpl: FetchFn, chain: EvmChain, method: string,
  params: unknown[], timeoutMs = 15_000): Promise<unknown> {
  const res = await fetchImpl(rpcUrlOf(chain), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const json = await res.json() as { result?: unknown; error?: { code?: number; message?: string; data?: unknown } };
  if (json.error) throw new RpcError(json.error.message ?? "RPC error", json.error.code, json.error.data);
  return json.result ?? null;
}

/** eth_call at the latest block; the raw return data. */
export async function ethCall(fetchImpl: FetchFn, chain: EvmChain, to: string, data: string): Promise<`0x${string}`> {
  const out = await evmRpc(fetchImpl, chain, "eth_call", [{ to, data }, "latest"]);
  return (typeof out === "string" ? out : "0x") as `0x${string}`;
}
