import { createPublicClient, getAddress, http, size, type Hex } from "viem";
import { mainnet } from "viem/chains";
import { normalize } from "viem/ens";
import { EVM_CHAINS, rpcUrlOf, type FetchFn } from "./evm.js";

/** "send 20 usdc to arpit.eth", "send 1 sol to arpit.sol": a name to the addresses it
 *  points at, and an address back to its name.
 *
 *  ENS goes through the Universal Resolver on Ethereum mainnet (viem, with
 *  CCIP-read on, so offchain and L2 names like `*.base.eth` resolve too),
 *  asking for each chain's own address by its ENSIP-11 coin type. SNS goes
 *  through Bonfida's own SDK against the server's Solana RPC. Nothing is
 *  invented: a chain the name has no address for is left out. */

export interface NameAddresses {
  ethereum?: string;
  base?: string;
  arbitrum?: string;
  optimism?: string;
  polygon?: string;
  solana?: string;
}

export interface NameAnswer {
  name: string;
  addresses: NameAddresses;
  avatar?: string;
  /** L2s whose address is only the name's Ethereum one: most names set
   *  nothing per chain, and an EOA is the same account everywhere, but a
   *  contract wallet isn't, so the app says so before sending. */
  inferred?: (keyof NameAddresses)[];
}

/** ENSIP-11: an EVM chain's coin type is 0x80000000 | chainId; ENSIP-19's
 *  default EVM address is chain 0. ETH is SLIP-44's 60, Solana 501. */
export const COIN_TYPES = {
  ethereum: 60,
  base: (0x80000000 | 8453) >>> 0,
  arbitrum: (0x80000000 | 42161) >>> 0,
  optimism: (0x80000000 | 10) >>> 0,
  polygon: (0x80000000 | 137) >>> 0,
  defaultEvm: 0x80000000,
  solana: 501,
} as const;

/** The three calls names need from ENS, so tests can stand in for viem. */
export interface EnsLookup {
  /** The raw record for a coin type: an address for 60, bytes otherwise. */
  address(name: string, coinType: number): Promise<Hex | null>;
  text(name: string, key: string): Promise<string | null>;
  /** The primary name an address has set, checked forward by the resolver. */
  name(address: `0x${string}`): Promise<string | null>;
}

export function viemEns(fetchImpl?: FetchFn): EnsLookup {
  const client = createPublicClient({
    chain: mainnet,
    transport: http(rpcUrlOf(EVM_CHAINS.ethereum), { timeout: 12_000, ...(fetchImpl ? { fetchFn: fetchImpl } : {}) }),
  });
  return {
    async address(name, coinType) {
      const out = await client.getEnsAddress({ name, coinType: BigInt(coinType) });
      return out ? out as Hex : null;
    },
    text: (name, key) => client.getEnsText({ name, key }),
    name: address => client.getEnsName({ address }),
  };
}

export interface SnsLookup {
  /** The wallet a .sol name points at. Null when the name isn't registered. */
  resolve(name: string): Promise<string | null>;
  /** The wallet's primary (favourite) .sol name. */
  primary(owner: string): Promise<string | null>;
}

/** Bonfida's SDK (and web3.js under it) is loaded on the first .sol lookup,
 *  not at every cold start. */
export function bonfidaSns(rpcUrl: string): SnsLookup {
  let sdk: Promise<{ connection: import("@solana/web3.js").Connection;
    web3: typeof import("@solana/web3.js"); sns: typeof import("@bonfida/spl-name-service") }> | undefined;
  const load = () => (sdk ??= (async () => {
    const [web3, sns] = await Promise.all([import("@solana/web3.js"), import("@bonfida/spl-name-service")]);
    return { connection: new web3.Connection(rpcUrl, "confirmed"), web3, sns };
  })());
  const kindOf = (err: unknown) => err instanceof Error ? err.name + " " + err.message : String(err);
  return {
    async resolve(name) {
      const { connection, sns } = await load();
      try {
        return (await sns.resolve(connection, name)).toBase58();
      } catch (err) {
        const kind = kindOf(err);
        if (/DomainDoesNotExist|does not exist|PdaOwnerNotAllowed|NoRecordData/i.test(kind)) return null;
        // The SDK stops resolving `.sol` itself once its SRS migration slot
        // passes ("UnsupportedTld"); the same name under `.sns` is the same
        // SNS registry entry, which the SDK documents as the fallback target.
        if (/UnsupportedTld|unsupported TLD/i.test(kind) && name.endsWith(".sol")) {
          try {
            return (await sns.resolve(connection, name.slice(0, -4) + ".sns")).toBase58();
          } catch (again) {
            if (/DomainDoesNotExist|does not exist|PdaOwnerNotAllowed|NoRecordData/i.test(kindOf(again))) return null;
            throw again;
          }
        }
        throw err;
      }
    },
    async primary(owner) {
      const { connection, web3, sns } = await load();
      try {
        const out = await sns.getPrimaryDomain(connection, new web3.PublicKey(owner));
        return out.stale ? null : `${out.reverse}.sol`;
      } catch (err) {
        if (/PrimaryDomainNotFound|not found|does not exist/i.test(kindOf(err))) return null;
        throw err;
      }
    },
  };
}

const B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/** Base58 (Bitcoin alphabet), for the 32 raw bytes ENS stores for Solana. */
export function base58(bytes: Uint8Array): string {
  let n = 0n;
  for (const b of bytes) n = n * 256n + BigInt(b);
  let out = "";
  while (n > 0n) {
    out = B58[Number(n % 58n)] + out;
    n /= 58n;
  }
  for (const b of bytes) {
    if (b !== 0) break;
    out = "1" + out;
  }
  return out;
}

function hexBytes(hex: Hex): Uint8Array {
  return Uint8Array.from(Buffer.from(hex.slice(2), "hex"));
}

/** A name ENS can normalise (ENSIP-15), or null for one it can't. */
export function ensName(raw: string): string | null {
  const name = raw.trim().replace(/^@/, "");
  if (!name.includes(".") || name.length > 255) return null;
  try {
    return normalize(name);
  } catch {
    return null;
  }
}

/** Every chain's address for an ENS name, or null when it has none. */
export async function resolveEns(ens: EnsLookup, name: string): Promise<NameAnswer | null> {
  // The Ethereum record is asked plainly, so a node that doesn't answer is
  // an error and not "no such name"; the rest are best-effort.
  const ask = (coinType: number) => ens.address(name, coinType).catch(() => null);
  const [eth, base, arbitrum, optimism, polygon, fallback, sol, avatar] = await Promise.all([
    ens.address(name, COIN_TYPES.ethereum), ask(COIN_TYPES.base), ask(COIN_TYPES.arbitrum),
    ask(COIN_TYPES.optimism), ask(COIN_TYPES.polygon), ask(COIN_TYPES.defaultEvm), ask(COIN_TYPES.solana),
    ens.text(name, "avatar").catch(() => null),
  ]);
  const evm = (raw: Hex | null) => raw && size(raw) === 20 ? getAddress(raw) : undefined;
  const addresses: NameAddresses = {};
  const inferred: (keyof NameAddresses)[] = [];
  if (evm(eth)) addresses.ethereum = evm(eth);
  for (const [chain, raw] of [["base", base], ["arbitrum", arbitrum], ["optimism", optimism], ["polygon", polygon]] as const) {
    const own = evm(raw) ?? evm(fallback);
    if (own) addresses[chain] = own;
    else if (addresses.ethereum) {
      addresses[chain] = addresses.ethereum;
      inferred.push(chain);
    }
  }
  if (sol && size(sol) === 32) addresses.solana = base58(hexBytes(sol));
  if (Object.keys(addresses).length === 0) return null;
  const answer: NameAnswer = { name, addresses };
  // Only a plain https picture: an NFT or IPFS avatar would have this server
  // fetch whatever URL a stranger wrote into their record.
  if (avatar && /^https:\/\/[^\s]+$/i.test(avatar) && avatar.length <= 512) answer.avatar = avatar;
  if (inferred.length) answer.inferred = inferred;
  return answer;
}

/** "send 5 usdc to alice.near": NEAR accounts are checked, not resolved. The
 *  account id is the address; view_account on a NEAR RPC
 *  (https://rpc.mainnet.near.org, or NEAR_RPC_URL) says whether it exists. */
export const NEAR_RPC = "https://rpc.mainnet.near.org";

/** A .near name (sub-accounts included), lowercase. */
export const NEAR_NAME = /^(?=.{2,64}$)(([a-z\d]+[-_])*[a-z\d]+\.)+near$/;
/** An implicit account: the hex of its own ed25519 key. */
export const NEAR_IMPLICIT_ACCOUNT = /^[0-9a-f]{64}$/;

export interface NearLookup {
  /** True when the account is on chain; false for UNKNOWN_ACCOUNT. Throws
   *  when the node can't say. */
  exists(account: string): Promise<boolean>;
}

export function nearRpc(fetchImpl: FetchFn = fetch, url?: string): NearLookup {
  const endpoint = () => (url ?? process.env.NEAR_RPC_URL ?? "").trim() || NEAR_RPC;
  return {
    async exists(account) {
      const res = await fetchImpl(endpoint(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: "glyf", method: "query",
          params: { request_type: "view_account", finality: "final", account_id: account } }),
        signal: AbortSignal.timeout(8_000),
      });
      const json = await res.json().catch(() => null) as { result?: unknown; error?: { cause?: { name?: string } } } | null;
      if (json?.result) return true;
      if (json?.error?.cause?.name === "UNKNOWN_ACCOUNT") return false;
      throw new Error(`near rpc ${res.status} ${json?.error?.cause?.name ?? "no answer"}`);
    },
  };
}
