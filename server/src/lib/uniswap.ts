import { concatHex, decodeFunctionResult, encodeFunctionData, getAddress, numberToHex, parseAbi } from "viem";
import { ethCall, type EvmChain, type FetchFn } from "./evm.js";
import { ERC20_ABI, wrappedNative, type EvmToken } from "./tokens.js";

/** Uniswap for "swap 0.05 eth to usdc on base", two ways with one answer.
 *
 *  With UNISWAP_API_KEY set, Uniswap's Trading API routes the trade (v2, v3
 *  and v4 pools) in its proxy-approval mode (`x-permit2-disabled`): the
 *  wallet approves Uniswap's swap proxy with a plain ERC-20 approve and sends
 *  a plain transaction, no Permit2 signature, which is what the phone's own
 *  key signs today. Without a key the server quotes Uniswap v3 itself:
 *  QuoterV2 over the four fee tiers in one Multicall3 eth_call, the best one
 *  wins, and the swap is SwapRouter02 calldata the wallet sends. Either way
 *  the phone gets plain {to, data, value, chainId} transactions to sign. */

export const TRADING_API = "https://trade-api.gateway.uniswap.org/v1";

/** Uniswap v3 per chain, from Uniswap's own deployment pages
 *  (developers.uniswap.org/docs/protocols/v3/deployments and the
 *  developers.uniswap.org/deployments.json feed, generated 2026-10-16). */
export const V3: Record<string, { quoterV2: `0x${string}`; swapRouter02: `0x${string}` }> = {
  ethereum: { quoterV2: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e", swapRouter02: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" },
  arbitrum: { quoterV2: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e", swapRouter02: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" },
  optimism: { quoterV2: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e", swapRouter02: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" },
  base: { quoterV2: "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", swapRouter02: "0x2626664c2603336E57B271c5C0b26F421741e481" },
  unichain: { quoterV2: "0x385A5cf5F83e99f7BB2852b6A19C3538b9FA7658", swapRouter02: "0x73855d06DE49d0fe4A9c42636Ba96c62da12FF9C" },
  "base-sepolia": { quoterV2: "0xC5290058841028F1614F3A6F0F5816cAd0df5E27", swapRouter02: "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4" },
  sepolia: { quoterV2: "0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3", swapRouter02: "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E" },
};

/** Multicall3: the same address on every chain above. */
export const MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11" as const;

/** v3's fee tiers in hundredths of a bip: 0.01%, 0.05%, 0.3%, 1%. */
export const FEE_TIERS = [100, 500, 3000, 10000] as const;

/** SwapRouter02's stand-in for "the router itself" as a recipient
 *  (swap-router-contracts libraries/Constants.sol, ADDRESS_THIS = address(2)),
 *  so it can unwrap WETH before paying out ETH. */
const ADDRESS_THIS = "0x0000000000000000000000000000000000000002" as const;

export const QUOTER_ABI = parseAbi([
  "function quoteExactInputSingle((address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, uint160 sqrtPriceLimitX96) params) returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)",
]);
/** QuoterV2's multi-pool quote: a packed path token, fee, token, fee, token. */
export const QUOTER_PATH_ABI = parseAbi([
  "function quoteExactInput(bytes path, uint256 amountIn) returns (uint256 amountOut, uint160[] sqrtPriceX96AfterList, uint32[] initializedTicksCrossedList, uint256 gasEstimate)",
]);
export const ROUTER_ABI = parseAbi([
  "function exactInputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96) params) payable returns (uint256 amountOut)",
  "function exactInput((bytes path, address recipient, uint256 amountIn, uint256 amountOutMinimum) params) payable returns (uint256 amountOut)",
  "function multicall(uint256 deadline, bytes[] data) payable returns (bytes[] results)",
  "function unwrapWETH9(uint256 amountMinimum, address recipient) payable",
]);
export const MULTICALL3_ABI = parseAbi([
  "struct Call3 { address target; bool allowFailure; bytes callData; }",
  "struct Result { bool success; bytes returnData; }",
  "function aggregate3(Call3[] calls) payable returns (Result[] returnData)",
]);
export const WETH_ABI = parseAbi([
  "function deposit() payable",
  "function withdraw(uint256 wad)",
]);

/** A transaction for the wallet to sign as it is. `value` is wei, decimal. */
export interface PlainTx {
  to: `0x${string}`;
  data: `0x${string}`;
  value: string;
  chainId: number;
  /** A gas limit when the source suggested one; the wallet may estimate. */
  gas?: string;
}

export interface V3Quote {
  amountOut: bigint;
  fee: number;
  gasEstimate: bigint;
  /** A two-pool route: in → via → out, with each pool's fee. */
  via?: `0x${string}`;
  fees?: [number, number];
}

/** v3's packed path: token (20 bytes), fee (3 bytes), token, fee, token. */
export function v3Path(tokens: `0x${string}`[], fees: number[]): `0x${string}` {
  const parts: `0x${string}`[] = [];
  tokens.forEach((t, i) => {
    parts.push(t.toLowerCase() as `0x${string}`);
    if (i < fees.length) parts.push(numberToHex(fees[i], { size: 3 }));
  });
  return concatHex(parts);
}

/** Two-pool routes through each of `mids` (WETH, USDC), every fee pair,
 *  in one eth_call; the best one. For a pair with no pool of its own. */
export async function quoteV3TwoHop(fetchImpl: FetchFn, chain: EvmChain, r: {
  tokenIn: `0x${string}`; tokenOut: `0x${string}`; amountIn: bigint;
}, mids: `0x${string}`[]): Promise<V3Quote | null> {
  const v3 = V3[chain.key];
  const via = mids.filter(m => m.toLowerCase() !== r.tokenIn.toLowerCase() && m.toLowerCase() !== r.tokenOut.toLowerCase());
  if (!v3 || via.length === 0) return null;
  const routes = via.flatMap(mid => FEE_TIERS.flatMap(a => FEE_TIERS.map(b => ({ mid, fees: [a, b] as [number, number] }))));
  const calls = routes.map(x => ({
    target: v3.quoterV2,
    allowFailure: true,
    callData: encodeFunctionData({ abi: QUOTER_PATH_ABI, functionName: "quoteExactInput",
      args: [v3Path([r.tokenIn, x.mid, r.tokenOut], x.fees), r.amountIn] }),
  }));
  const data = await ethCall(fetchImpl, chain, MULTICALL3,
    encodeFunctionData({ abi: MULTICALL3_ABI, functionName: "aggregate3", args: [calls] }));
  const results = decodeFunctionResult({ abi: MULTICALL3_ABI, functionName: "aggregate3", data });
  let best: V3Quote | null = null;
  routes.forEach((x, i) => {
    const res = results[i];
    if (!res?.success || res.returnData === "0x") return;
    try {
      const [amountOut, , , gasEstimate] = decodeFunctionResult({ abi: QUOTER_PATH_ABI, functionName: "quoteExactInput", data: res.returnData });
      if (amountOut > 0n && (!best || amountOut > best.amountOut)) {
        best = { amountOut, fee: x.fees[0], gasEstimate, via: x.mid, fees: x.fees };
      }
    } catch {
      // No answer from this route.
    }
  });
  return best;
}

/** The contract a v3 swap trades: WETH stands in for ETH. */
export function v3Address(chain: EvmChain, token: EvmToken): `0x${string}` | null {
  if (!token.native) return token.address;
  return wrappedNative(chain)?.address ?? null;
}

/** The best single-pool v3 quote for each request, all in one eth_call
 *  (Multicall3 with failures allowed: a tier with no pool just reverts).
 *  Null for a request no tier can fill. */
export async function quoteV3Many(fetchImpl: FetchFn, chain: EvmChain,
  requests: { tokenIn: `0x${string}`; tokenOut: `0x${string}`; amountIn: bigint }[]): Promise<(V3Quote | null)[]> {
  const v3 = V3[chain.key];
  if (!v3 || requests.length === 0) return requests.map(() => null);
  const calls = requests.flatMap(r => FEE_TIERS.map(fee => ({
    target: v3.quoterV2,
    allowFailure: true,
    callData: encodeFunctionData({ abi: QUOTER_ABI, functionName: "quoteExactInputSingle",
      args: [{ tokenIn: r.tokenIn, tokenOut: r.tokenOut, amountIn: r.amountIn, fee, sqrtPriceLimitX96: 0n }] }),
  })));
  const data = await ethCall(fetchImpl, chain, MULTICALL3,
    encodeFunctionData({ abi: MULTICALL3_ABI, functionName: "aggregate3", args: [calls] }));
  const results = decodeFunctionResult({ abi: MULTICALL3_ABI, functionName: "aggregate3", data });
  return requests.map((_, i) => {
    let best: V3Quote | null = null;
    FEE_TIERS.forEach((fee, j) => {
      const r = results[i * FEE_TIERS.length + j];
      if (!r?.success || r.returnData === "0x") return;
      try {
        const [amountOut, , , gasEstimate] = decodeFunctionResult({ abi: QUOTER_ABI,
          functionName: "quoteExactInputSingle", data: r.returnData });
        if (amountOut > 0n && (!best || amountOut > best.amountOut)) best = { amountOut, fee, gasEstimate };
      } catch {
        // A tier whose answer doesn't decode is a tier without a quote.
      }
    });
    return best;
  });
}

/** SwapRouter02 calldata for an exact-input single-pool swap. ETH in rides
 *  as `value` (the router wraps it); ETH out is swapped to the router and
 *  unwrapped to the recipient in the same multicall. */
export function v3SwapTx(chain: EvmChain, args: {
  sell: EvmToken; buy: EvmToken; amountIn: bigint; minOut: bigint; fee: number;
  recipient: `0x${string}`; deadline: bigint;
  /** A two-pool route (quoteV3TwoHop): exactInput over the packed path. */
  via?: `0x${string}`; fees?: [number, number];
}): PlainTx {
  const v3 = V3[chain.key];
  const tokenIn = v3Address(chain, args.sell)!;
  const tokenOut = v3Address(chain, args.buy)!;
  const recipient = args.buy.native ? ADDRESS_THIS : args.recipient;
  const swap = args.via && args.fees
    ? encodeFunctionData({ abi: ROUTER_ABI, functionName: "exactInput", args: [{
      path: v3Path([tokenIn, args.via, tokenOut], args.fees), recipient,
      amountIn: args.amountIn, amountOutMinimum: args.minOut,
    }] })
    : encodeFunctionData({ abi: ROUTER_ABI, functionName: "exactInputSingle", args: [{
      tokenIn, tokenOut, fee: args.fee, recipient,
      amountIn: args.amountIn, amountOutMinimum: args.minOut, sqrtPriceLimitX96: 0n,
    }] });
  const steps: `0x${string}`[] = [swap];
  if (args.buy.native) {
    steps.push(encodeFunctionData({ abi: ROUTER_ABI, functionName: "unwrapWETH9", args: [args.minOut, args.recipient] }));
  }
  return {
    to: v3.swapRouter02,
    data: encodeFunctionData({ abi: ROUTER_ABI, functionName: "multicall", args: [args.deadline, steps] }),
    value: args.sell.native ? args.amountIn.toString() : "0",
    chainId: chain.id,
  };
}

/** ETH ↔ WETH is a wrap, not a trade: WETH's own deposit and withdraw. */
export function wrapTx(chain: EvmChain, sell: EvmToken, amountIn: bigint): PlainTx {
  const weth = wrappedNative(chain)!.address;
  return sell.native
    ? { to: weth, data: encodeFunctionData({ abi: WETH_ABI, functionName: "deposit" }), value: amountIn.toString(), chainId: chain.id }
    : { to: weth, data: encodeFunctionData({ abi: WETH_ABI, functionName: "withdraw", args: [amountIn] }), value: "0", chainId: chain.id };
}

/** The ERC-20 approve the swap needs, when the allowance is short: exactly
 *  the amount, never unlimited. Mainnet USDT refuses to change a non-zero
 *  allowance, so it gets a reset to zero first. */
export async function v3Approval(fetchImpl: FetchFn, chain: EvmChain, token: EvmToken,
  owner: `0x${string}`, amount: bigint): Promise<{ approval?: PlainTx; approvalReset?: PlainTx }> {
  if (token.native) return {};
  const spender = V3[chain.key].swapRouter02;
  const data = await ethCall(fetchImpl, chain, token.address,
    encodeFunctionData({ abi: ERC20_ABI, functionName: "allowance", args: [owner, spender] }));
  const current = decodeFunctionResult({ abi: ERC20_ABI, functionName: "allowance", data });
  if (current >= amount) return {};
  const approve = (value: bigint): PlainTx => ({ to: token.address,
    data: encodeFunctionData({ abi: ERC20_ABI, functionName: "approve", args: [spender, value] }),
    value: "0", chainId: chain.id });
  const usdtMainnet = chain.key === "ethereum"
    && token.address === getAddress("0xdAC17F958D2ee523a2206206994597C13D831ec7");
  return { approval: approve(amount), ...(usdtMainnet && current > 0n ? { approvalReset: approve(0n) } : {}) };
}

/** Uniswap's Trading API writes a gas coin as the zero address. */
export function apiToken(token: EvmToken): string {
  return token.native ? "0x0000000000000000000000000000000000000000" : token.address;
}

/** A Trading API transaction in the shape the phone signs. */
export function plainFromApi(tx: { to?: string; data?: string; value?: string; chainId?: number; gasLimit?: string }, chainId: number): PlainTx | null {
  if (!tx?.to || !tx.data || tx.data === "0x") return null;
  return {
    to: getAddress(tx.to),
    data: tx.data as `0x${string}`,
    value: BigInt(tx.value || "0").toString(),
    chainId: tx.chainId ?? chainId,
    ...(tx.gasLimit ? { gas: BigInt(tx.gasLimit).toString() } : {}),
  };
}
