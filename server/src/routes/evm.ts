import type { FastifyInstance } from "fastify";
import { decodeFunctionResult, encodeFunctionData, formatUnits, getAddress, isAddress } from "viem";
import { z } from "zod";
import { chainOf, ethCall, evmRpc, RpcError, type FetchFn } from "../lib/evm.js";
import { ERC20_ABI, tokensOn } from "../lib/tokens.js";

/**
 * The Ethereum wallet's node calls, the EVM twin of POST /wallet/rpc.
 *
 * The wallet lives on the phone: it holds its own key, builds each
 * EIP-1559 transaction and signs it there. What it needs from a node goes
 * through here, to the chain's public RPC (or the one its variable names),
 * so the app ships no RPC list and a keyed node can be swapped in later
 * without an update. Only the calls a wallet makes are carried; the server
 * never holds or sees a key that can move money.
 */

const ALLOWED = new Set([
  "eth_call",
  "eth_getBalance",
  "eth_estimateGas",
  "eth_gasPrice",
  "eth_maxPriorityFeePerGas",
  "eth_feeHistory",
  "eth_getTransactionCount",
  "eth_sendRawTransaction",
  "eth_getTransactionReceipt",
  "eth_blockNumber",
  "eth_chainId",
  "eth_getLogs",
]);

const RpcSchema = z.object({
  chain: z.union([z.string().min(1).max(40), z.number().int().positive()]),
  method: z.string().min(1).max(40),
  params: z.array(z.unknown()).max(4).default([]),
});

export interface EvmDeps {
  fetchImpl?: FetchFn;
}

export function evmRoutes(app: FastifyInstance, deps: EvmDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;

  app.post("/evm/rpc", async (req, reply) => {
    const parsed = RpcSchema.safeParse(req.body);
    const chain = parsed.success ? chainOf(parsed.data.chain) : null;
    if (!parsed.success || !chain || !ALLOWED.has(parsed.data.method)) {
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const { method, params } = parsed.data;
    try {
      const result = await evmRpc(fetchImpl, chain, method, params);
      // Addresses, amounts and transactions stay out of the log.
      req.log.info({ chain: chain.key, method }, "evm_rpc");
      return { ok: true, result };
    } catch (err) {
      if (err instanceof RpcError) {
        // The node's own words ("insufficient funds for gas * price + value"),
        // which the app turns into something a person can act on.
        return reply.code(400).send({ ok: false, error: err.message, code: err.code,
          ...(err.data !== undefined ? { data: err.data } : {}) });
      }
      req.log.warn({ chain: chain.key, method, err: err instanceof Error ? err.message : String(err) }, "evm_rpc_failed");
      return reply.code(502).send({ ok: false, error: `${chain.name} didn't answer. Try again in a moment` });
    }
  });

  /** ?chain=base — the coins the keyboard can name there, gas coin first. */
  app.get("/evm/tokens", async (req, reply) => {
    const chain = chainOf((req.query as { chain?: string }).chain ?? "");
    if (!chain) return reply.code(400).send({ ok: false, error: "chain?" });
    reply.header("cache-control", "private, max-age=3600");
    return { ok: true, chain: { key: chain.key, id: chain.id, name: chain.name, native: chain.native },
      tokens: tokensOn(chain) };
  });

  /** ?chain=base&address=0x… — the gas coin and every listed token, each
   *  as base units and as a decimal. A token whose node call fails is left
   *  out rather than shown as zero. */
  app.get("/evm/balances", async (req, reply) => {
    const q = req.query as { chain?: string; address?: string };
    const chain = chainOf(q.chain ?? "");
    const raw = (q.address ?? "").trim();
    if (!chain || !isAddress(raw, { strict: false })) return reply.code(400).send({ ok: false, error: "chain and address?" });
    const owner = getAddress(raw);
    const read = async (token: ReturnType<typeof tokensOn>[number]) => {
      let units: bigint;
      if (token.native) {
        units = BigInt(String(await evmRpc(fetchImpl, chain, "eth_getBalance", [owner, "latest"])));
      } else {
        const data = await ethCall(fetchImpl, chain, token.address,
          encodeFunctionData({ abi: ERC20_ABI, functionName: "balanceOf", args: [owner] }));
        units = decodeFunctionResult({ abi: ERC20_ABI, functionName: "balanceOf", data });
      }
      return { ...token, raw: units.toString(), amount: formatUnits(units, token.decimals) };
    };
    const results = await Promise.allSettled(tokensOn(chain).map(read));
    const balances = results.flatMap(r => r.status === "fulfilled" ? [r.value] : []);
    if (balances.length === 0) {
      return reply.code(502).send({ ok: false, error: `${chain.name} didn't answer. Try again in a moment` });
    }
    req.log.info({ chain: chain.key, tokens: balances.length }, "evm_balances");
    return { ok: true, chain: chain.key, address: owner, balances };
  });
}
