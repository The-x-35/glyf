import { decodeFunctionResult, encodeFunctionData, getAddress, isAddress, parseAbi } from "viem";
import { ethCall, type EvmChain, type FetchFn } from "./evm.js";

/** The coins the keyboard can name per chain, so "swap 0.05 eth to usdc on
 *  base" needs no lookup: symbol → address and decimals.
 *
 *  Only issuers' own addresses (Circle for USDC, Tether for USDT, Sky for
 *  DAI, BitGo for WBTC, Coinbase for cbBTC, Chainlink for LINK, Uniswap's
 *  docs for WETH), and only where the issuer lists the chain: a symbol a
 *  chain doesn't have here is better unknown than a lookalike. Each address
 *  was read back on its chain (symbol() and decimals()) on 2026-11-06.
 *  Anything else is still reachable by pasting its address. */

export interface EvmToken {
  symbol: string;
  name: string;
  address: `0x${string}`;
  decimals: number;
  /** The chain's gas coin, which has no contract. */
  native?: true;
}

/** How Flash (and most aggregators) write a chain's gas coin. Uniswap's
 *  Trading API writes it as the zero address instead (routes/uniswap.ts). */
export const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" as const;

const t = (symbol: string, name: string, address: string, decimals: number): EvmToken =>
  ({ symbol, name, address: getAddress(address), decimals });

const WETH_OP_STACK = "0x4200000000000000000000000000000000000006";

const LISTS: Record<string, EvmToken[]> = {
  ethereum: [
    t("WETH", "Wrapped Ether", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 18),
    t("USDC", "USD Coin", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 6),
    t("USDT", "Tether USD", "0xdAC17F958D2ee523a2206206994597C13D831ec7", 6),
    t("DAI", "Dai Stablecoin", "0x6B175474E89094C44Da98b954EedeAC495271d0F", 18),
    t("WBTC", "Wrapped BTC", "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", 8),
    t("cbBTC", "Coinbase Wrapped BTC", "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", 8),
    t("UNI", "Uniswap", "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", 18),
    t("LINK", "Chainlink", "0x514910771AF9Ca656af840dff83E8264EcF986CA", 18),
  ],
  base: [
    t("WETH", "Wrapped Ether", WETH_OP_STACK, 18),
    t("USDC", "USD Coin", "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", 6),
    t("DAI", "Dai Stablecoin", "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb", 18),
    t("cbBTC", "Coinbase Wrapped BTC", "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", 8),
    t("LINK", "Chainlink", "0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196", 18),
  ],
  arbitrum: [
    t("WETH", "Wrapped Ether", "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", 18),
    t("USDC", "USD Coin", "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", 6),
    t("USDT", "USD₮0 (Tether)", "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", 6),
    t("DAI", "Dai Stablecoin", "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", 18),
    t("WBTC", "Wrapped BTC", "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", 8),
    t("UNI", "Uniswap", "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0", 18),
    t("LINK", "Chainlink", "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4", 18),
    t("ARB", "Arbitrum", "0x912CE59144191C1204E64559FE8253a0e49E6548", 18),
  ],
  optimism: [
    t("WETH", "Wrapped Ether", WETH_OP_STACK, 18),
    t("USDC", "USD Coin", "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", 6),
    t("USDT", "Tether USD", "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", 6),
    t("DAI", "Dai Stablecoin", "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", 18),
    t("WBTC", "Wrapped BTC", "0x68f180fcCe6836688e9084f035309E29Bf0A2095", 8),
    t("UNI", "Uniswap", "0x6fd9d7AD17242c41f7131d257212c54A0e816691", 18),
    t("LINK", "Chainlink", "0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6", 18),
    t("OP", "Optimism", "0x4200000000000000000000000000000000000042", 18),
  ],
  unichain: [
    t("WETH", "Wrapped Ether", WETH_OP_STACK, 18),
    t("USDC", "USD Coin", "0x078D782b760474a361dDA0AF3839290b0EF57AD6", 6),
  ],
  // Test USDT named in Whitechain's hackathon brief (docs/ETHGLOBAL-MUMBAI.md).
  "whitechain-sepolia": [
    t("USDT", "Tether USD (test)", "0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7", 6),
  ],
  "arkiv-testnet": [],
  // Circle's testnet USDC; WETH from Uniswap's v3 deployment pages.
  "base-sepolia": [
    t("WETH", "Wrapped Ether", WETH_OP_STACK, 18),
    t("USDC", "USD Coin", "0x036CbD53842c5426634e7929541eC2318f3dCF7e", 6),
  ],
  sepolia: [
    t("WETH", "Wrapped Ether", "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", 18),
    t("USDC", "USD Coin", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", 6),
  ],
};

/** Names people type for a coin that isn't its ticker. */
const SYMBOL_ALIASES: Record<string, string> = {
  ether: "ETH", eth: "ETH", bitcoin: "WBTC", btc: "WBTC", usd: "USDC", dollar: "USDC",
  dollars: "USDC", tether: "USDT", chainlink: "LINK", uniswap: "UNI", dai: "DAI",
};

/** Dollar coins: one of them on either side of a trade prices it. */
export const STABLES = new Set(["USDC", "USDT", "DAI"]);

/** The chain's tokens, its gas coin first. */
export function tokensOn(chain: EvmChain): EvmToken[] {
  const native: EvmToken = { symbol: chain.native, name: chain.native === "ETH" ? "Ether" : chain.native,
    address: NATIVE, decimals: 18, native: true };
  return [native, ...(LISTS[chain.key] ?? [])];
}

/** The wrapped gas coin (WETH) where the chain has one listed. */
export function wrappedNative(chain: EvmChain): EvmToken | null {
  return (LISTS[chain.key] ?? []).find(x => x.symbol === `W${chain.native}`) ?? null;
}

/** A listed token by symbol ("usdc", "$eth", "bitcoin") or address. */
export function findToken(chain: EvmChain, query: string): EvmToken | null {
  const raw = query.trim().replace(/^\$/, "");
  const list = tokensOn(chain);
  if (isAddress(raw, { strict: false })) {
    const address = raw.toLowerCase();
    if (address === NATIVE.toLowerCase() || address === "0x0000000000000000000000000000000000000000") return list[0];
    return list.find(x => x.address.toLowerCase() === address) ?? null;
  }
  const lower = raw.toLowerCase();
  const symbol = (SYMBOL_ALIASES[lower] ?? raw).toUpperCase();
  // On a chain whose list has no WBTC (Base), "btc" means its cbBTC.
  const wanted = symbol === "WBTC" && !list.some(x => x.symbol === "WBTC") ? "CBBTC" : symbol;
  return list.find(x => x.symbol.toUpperCase() === wanted) ?? null;
}

const ERC20 = parseAbi([
  "function symbol() view returns (string)",
  "function name() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);
export { ERC20 as ERC20_ABI };

/** A listed token, or for a pasted address that isn't listed, what its
 *  contract says about itself. Null when it isn't a token at all. */
export async function resolveToken(fetchImpl: FetchFn, chain: EvmChain, query: string): Promise<EvmToken | null> {
  const listed = findToken(chain, query);
  if (listed || !isAddress(query.trim(), { strict: false })) return listed;
  const address = getAddress(query.trim());
  const read = async (functionName: "symbol" | "name" | "decimals") => {
    const data = await ethCall(fetchImpl, chain, address, encodeFunctionData({ abi: ERC20, functionName }));
    return decodeFunctionResult({ abi: ERC20, functionName, data });
  };
  try {
    const [symbol, name, decimals] = await Promise.all([read("symbol"), read("name"), read("decimals")]);
    return { symbol: String(symbol), name: String(name), address, decimals: Number(decimals) };
  } catch {
    return null;
  }
}

/** Solana's side for Flash, which trades there too: the mints the keyboard
 *  can name. SOL is the wSOL mint Flash quotes against (with
 *  svmUseNativeSOL to spend native SOL). */
export const SOLANA_TOKENS: { symbol: string; name: string; address: string; decimals: number; native?: true }[] = [
  { symbol: "SOL", name: "Solana", address: "So11111111111111111111111111111111111111112", decimals: 9, native: true },
  { symbol: "USDC", name: "USD Coin", address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6 },
  { symbol: "USDT", name: "Tether USD", address: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", decimals: 6 },
];

export function findSolanaToken(query: string) {
  const raw = query.trim().replace(/^\$/, "");
  const symbol = (SYMBOL_ALIASES[raw.toLowerCase()] ?? raw).toUpperCase();
  return SOLANA_TOKENS.find(x => x.address === raw || x.symbol === symbol || (symbol === "WSOL" && x.symbol === "SOL")) ?? null;
}
