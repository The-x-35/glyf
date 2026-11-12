import { formatUnits, parseUnits } from "viem";
import type { FetchFn } from "./evm.js";
import { NEAR_IMPLICIT_ACCOUNT, NEAR_NAME, NEAR_RPC } from "./names.js";
import { SPUTNIK } from "./payrequests.js";

/**
 * The group pot (docs/NEAR-SPEC.md, "The group pot"): a Sputnik DAO v2
 * treasury (trip.sputnik-dao.near) that pay links fill and whose members
 * vote payouts out. Read-only here, through NEAR RPC function-call views
 * (keyless; https://rpc.mainnet.near.org or NEAR_RPC_URL):
 *
 * - get_config: the DAO's name and purpose.
 * - get_policy: roles, members, vote policies, bond and voting period.
 * - get_available_amount (else view_account less storage): NEAR it can pay.
 * - ft_balance_of on USDC and USDT, mt_batch_balance_of on intents.near:
 *   stablecoins held directly or inside NEAR Intents (as Trezu keeps them).
 * - get_last_proposal_id + get_proposals: the latest proposals, with votes.
 *
 * Nothing is signed. A payout is proposed in Trezu (NEAR DevHub's Sputnik
 * app, https://trezu.app), whose payments page takes a recipient and token
 * from its URL (nt-fe/app/(treasury)/[treasuryId]/payments/page.tsx and
 * utils/payments-deep-link.ts in github.com/NEAR-DevHub/trezu: `address`,
 * `token`, `network`); the amount and note are typed there.
 */

export const TREZU = "https://trezu.app";
export const INTENTS_CONTRACT = "intents.near";
/** Native USDC and USDT on NEAR, the stablecoins a pot most often holds. */
export const NEAR_USDC = "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1";
export const NEAR_USDT = "usdt.tether-token.near";

interface FtInfo { symbol: string; decimals: number }
/** Tokens whose decimals are known without asking the token. */
const KNOWN_FT: Record<string, FtInfo> = {
  "": { symbol: "NEAR", decimals: 24 },
  [NEAR_USDC]: { symbol: "USDC", decimals: 6 },
  [NEAR_USDT]: { symbol: "USDT", decimals: 6 },
  "wrap.near": { symbol: "wNEAR", decimals: 24 },
  "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.factory.bridge.near": { symbol: "USDC.e", decimals: 6 },
  "dac17f958d2ee523a2206206994597c13d831ec7.factory.bridge.near": { symbol: "USDT.e", decimals: 6 },
  "nbtc.bridge.near": { symbol: "BTC", decimals: 8 },
};
/** What a payout can be proposed in from Glyf: the pot's coin, by name. */
export const POT_COINS: Record<string, string> = { NEAR: "", USDC: NEAR_USDC, USDT: NEAR_USDT };

/** A failure in plain words, with the status to send. */
export class PotError extends Error {
  constructor(readonly status: 400 | 404 | 502, message: string) {
    super(message);
  }
}

export interface NearViews {
  /** A contract view's JSON. Throws PotError(404) for an account or method
   *  that isn't there, PotError(502) when NEAR can't be reached. */
  view<T = unknown>(account: string, method: string, args?: Record<string, unknown>): Promise<T>;
  account(account: string): Promise<{ amount: string; locked: string; storage_usage: number }>;
}

export function nearViews(fetchImpl: FetchFn = fetch, url?: string): NearViews {
  const endpoint = () => (url ?? process.env.NEAR_RPC_URL ?? "").trim() || NEAR_RPC;
  async function query(params: Record<string, unknown>): Promise<any> {
    let res: Response;
    try {
      res = await fetchImpl(endpoint(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: "glyf", method: "query", params: { finality: "final", ...params } }),
        signal: AbortSignal.timeout(8_000),
      });
    } catch {
      throw new PotError(502, "NEAR didn't answer. Try again in a moment");
    }
    const json = await res.json().catch(() => null) as any;
    const cause = json?.error?.cause?.name;
    if (cause === "UNKNOWN_ACCOUNT" || cause === "NO_CONTRACT_CODE") throw new PotError(404, "no account");
    // A view that panics or isn't there comes back as result.error.
    if (json?.result?.error) throw new PotError(404, String(json.result.error).slice(0, 200));
    if (!json?.result) throw new PotError(502, "NEAR didn't answer. Try again in a moment");
    return json.result;
  }
  return {
    async view(account, method, args = {}) {
      const r = await query({ request_type: "call_function", account_id: account, method_name: method,
        args_base64: Buffer.from(JSON.stringify(args)).toString("base64") });
      if (!Array.isArray(r.result)) throw new PotError(502, "NEAR didn't answer. Try again in a moment");
      try {
        return JSON.parse(Buffer.from(r.result).toString("utf8"));
      } catch {
        throw new PotError(502, "NEAR sent back something Glyf can't read");
      }
    },
    async account(account) {
      const r = await query({ request_type: "view_account", account_id: account });
      return { amount: String(r.amount), locked: String(r.locked ?? "0"), storage_usage: Number(r.storage_usage ?? 0) };
    },
  };
}

// ---- Policy: who's in, who votes, how many approvals a payout needs ----

type Threshold = string | [number, number];
interface VotePolicy { weight_kind?: string; quorum?: string; threshold?: Threshold }
interface Role { name: string; kind: unknown; permissions: string[]; vote_policy: Record<string, VotePolicy> }
export interface Policy {
  roles: Role[];
  default_vote_policy: VotePolicy;
  proposal_bond: string;
  proposal_period: string;
}

/** The policy label Sputnik votes a proposal kind under ("Transfer" is
 *  "transfer", "FunctionCall" is "call"): sputnik-dao-contract's
 *  ProposalKind::to_policy_label. */
export function policyLabel(kind: string): string {
  const special: Record<string, string> = { FunctionCall: "call", SetStakingContract: "set_vote_token" };
  if (special[kind]) return special[kind];
  return kind.replace(/^Change/, "").replace(/([a-z])([A-Z])/g, "$1_$2").toLowerCase();
}

function groupOf(role: Role): string[] | null {
  const k = role.kind as any;
  return k && typeof k === "object" && Array.isArray(k.Group) ? k.Group.filter((m: unknown) => typeof m === "string") : null;
}

function allows(role: Role, label: string, action: string): boolean {
  return role.permissions.some(p => p === `${label}:${action}` || p === `*:${action}` || p === `${label}:*` || p === "*:*");
}

/** Approvals a group role needs to pass a proposal of `label`, as the
 *  contract counts it (VotePolicy::to_weight, then the quorum), or null
 *  when the vote is weighted by tokens or open to everyone. */
export function approvalsNeeded(policy: Policy, role: Role, label: string): number | null {
  const group = groupOf(role);
  if (!group) return null;
  const vp = role.vote_policy?.[label] ?? policy.default_vote_policy;
  if ((vp.weight_kind ?? "RoleWeight") !== "RoleWeight") return null;
  const total = group.length;
  const t = vp.threshold ?? [1, 2];
  let weight: number;
  if (Array.isArray(t)) weight = Math.min(Math.floor((t[0] * total) / t[1]) + 1, total);
  else weight = Math.min(Number(t), total);
  const quorum = Number(vp.quorum ?? "0");
  return Math.max(Number.isFinite(quorum) ? quorum : 0, weight);
}

export interface VoteRule {
  /** The role whose votes pass it soonest. */
  role: string;
  approvals: number;
  of: number;
  words: string;
}

/** How a proposal of `label` passes: the voting group role that needs the
 *  fewest approvals (any role that reaches its threshold passes it). */
export function voteRule(policy: Policy, label: string): VoteRule | null {
  let best: VoteRule | null = null;
  for (const role of policy.roles) {
    if (!allows(role, label, "VoteApprove")) continue;
    const need = approvalsNeeded(policy, role, label);
    const group = groupOf(role);
    if (need === null || !group || group.length === 0) continue;
    if (!best || need < best.approvals) best = { role: role.name, approvals: need, of: group.length, words: `${need} of ${group.length}` };
  }
  return best;
}

/** Everyone named in a group role, once each, in the policy's order. */
export function membersOf(policy: Policy): string[] {
  const seen = new Set<string>();
  for (const role of policy.roles) for (const m of groupOf(role) ?? []) seen.add(m);
  return [...seen];
}

/** Who may file a payout: group members whose role may add a transfer
 *  proposal, or "everyone" when the policy lets anyone. */
export function proposers(policy: Policy): string[] | "everyone" {
  const out = new Set<string>();
  for (const role of policy.roles) {
    if (!allows(role, "transfer", "AddProposal")) continue;
    const k = role.kind as any;
    if (k === "Everyone") return "everyone";
    for (const m of groupOf(role) ?? []) out.add(m);
  }
  return [...out];
}

// ---- Proposals ----

export type ProposalStatus = "InProgress" | "Approved" | "Rejected" | "Removed" | "Expired" | "Moved" | "Failed";

export interface PotProposal {
  id: number;
  kind: string;
  description: string;
  /** Transfers only: whole coins, the coin, and who gets it. */
  amount: string | null;
  coin: string | null;
  receiver: string | null;
  proposer: string;
  status: ProposalStatus;
  /** Open, but past its voting period (the contract marks it on the next vote). */
  votes: { approve: number; reject: number; remove: number };
  voters: Record<string, string>;
  /** Approvals still needed to pass, while it's open. */
  approvalsNeeded: number | null;
  submitted: string;
  expires: string;
  url: string;
}

const NS_PER_MS = 1_000_000n;
const iso = (ns: bigint) => new Date(Number(ns / NS_PER_MS)).toISOString();
/** Whole coins without trailing zeros, at most 6 places. */
export function coinAmount(base: string, decimals: number): string {
  const whole = formatUnits(BigInt(base), decimals);
  const [i, f = ""] = whole.split(".");
  const cut = f.slice(0, 6).replace(/0+$/, "");
  return cut ? `${i}.${cut}` : i;
}

function plainDescription(raw: unknown): string {
  return String(raw ?? "").replace(/<br\s*\/?>/gi, "\n").replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, " ").trim().slice(0, 280);
}

// ---- The pot ----

export interface PotBalance {
  /** NEAR the DAO can pay out: its balance less storage and bonds held. */
  near: string;
  tokens: { symbol: string; amount: string; contract: string; inIntents: boolean }[];
}

export interface PotView {
  ok: true;
  dao: string;
  name: string;
  purpose: string;
  balance: PotBalance;
  members: string[];
  memberCount: number;
  proposers: string[] | "everyone";
  /** How a payout (a Transfer proposal) passes. */
  threshold: VoteRule | null;
  bond: string;
  votingDays: number;
  proposals: PotProposal[];
  lastProposalId: number;
  /** Proposals still open for votes, of those shown. */
  open: number;
  /** One line to put in the chat: "The trip pot holds 42.5 NEAR · 140.5
   *  USDC. 4 members, payouts need 2 of 3. 1 payout open". */
  text: string;
  links: { trezu: string; propose: string };
}

const MAX_MEMBERS = 50;
const MAX_PROPOSALS = 10;
const KEEP_MS = 30_000;

export interface PotDeps { views?: NearViews; fetchImpl?: FetchFn; now?: () => number }

export class Pots {
  private readonly views: NearViews;
  private readonly now: () => number;
  private readonly kept = new Map<string, { at: number; view: PotView }>();
  private readonly ft = new Map<string, FtInfo | null>();

  constructor(deps: PotDeps = {}) {
    this.views = deps.views ?? nearViews(deps.fetchImpl);
    this.now = deps.now ?? Date.now;
  }

  /** A pot's balance, members, payout rule and latest proposals, kept 30 s. */
  async pot(dao: string): Promise<PotView> {
    const id = dao.trim().toLowerCase();
    if (!SPUTNIK.test(id)) throw new PotError(400, "A pot is a Sputnik DAO, like trip.sputnik-dao.near");
    const hit = this.kept.get(id);
    if (hit && this.now() - hit.at < KEEP_MS) return hit.view;
    const v = this.views;
    const notDao = (err: unknown) => {
      if (err instanceof PotError && err.status === 404) throw new PotError(404, `No Sputnik DAO ${id}`);
      throw err;
    };
    const [config, policy, last] = await Promise.all([
      v.view<{ name?: string; purpose?: string }>(id, "get_config").catch(notDao),
      v.view<Policy>(id, "get_policy").catch(notDao),
      v.view<number>(id, "get_last_proposal_id").catch(notDao),
    ]);
    if (!policy || !Array.isArray(policy.roles)) throw new PotError(404, `No Sputnik DAO ${id}`);
    const from = Math.max(0, Number(last) - MAX_PROPOSALS);
    const [balance, rows] = await Promise.all([
      this.balance(id),
      Number(last) > 0 ? v.view<any[]>(id, "get_proposals", { from_index: from, limit: MAX_PROPOSALS }).catch(() => []) : Promise.resolve([]),
    ]);
    const proposals = await Promise.all((Array.isArray(rows) ? rows : []).map(r => this.proposal(id, policy, r)));
    const members = membersOf(policy);
    const shown = proposals.filter((p): p is PotProposal => p !== null).sort((a, b) => b.id - a.id);
    const open = shown.filter(p => p.status === "InProgress").length;
    const name = String(config?.name ?? id.replace(/\.sputnik-dao\.near$/, ""));
    const rule = voteRule(policy, "transfer");
    const sums = new Map<string, number>();
    for (const t of balance.tokens) sums.set(t.symbol, (sums.get(t.symbol) ?? 0) + Number(t.amount));
    const nearTotal = Number(balance.near) + (sums.get("NEAR") ?? 0);
    sums.delete("NEAR");
    const two = (n: number) => String(Math.round(n * 100) / 100);
    const holds = [`${two(nearTotal)} NEAR`, ...[...sums].map(([sym, n]) => `${two(n)} ${sym}`)].join(" · ");
    const text = `The ${name} pot holds ${holds}. ${members.length} ${members.length === 1 ? "member" : "members"}`
      + `${rule ? `, payouts need ${rule.words}` : ""}.${open ? ` ${open} ${open === 1 ? "proposal" : "proposals"} open` : ""}`;
    const view: PotView = {
      ok: true, dao: id, name,
      purpose: String(config?.purpose ?? "").slice(0, 200),
      balance, members: members.slice(0, MAX_MEMBERS), memberCount: members.length,
      proposers: proposers(policy),
      threshold: rule,
      bond: coinAmount(String(policy.proposal_bond ?? "0"), 24),
      votingDays: Math.round(Number(BigInt(String(policy.proposal_period ?? "0")) / (NS_PER_MS * 1000n)) / 86400 * 10) / 10,
      proposals: shown,
      lastProposalId: Number(last), open, text,
      links: { trezu: `${TREZU}/${id}/dashboard`, propose: `${TREZU}/${id}/payments` },
    };
    this.kept.set(id, { at: this.now(), view });
    return view;
  }

  private async balance(dao: string): Promise<PotBalance> {
    const v = this.views;
    const near = await v.view<string>(dao, "get_available_amount").then(String).catch(async () => {
      // Some DAOs' get_available_amount panics (it subtracts past zero):
      // the account's balance less what its storage holds is close enough.
      const a = await v.account(dao);
      const free = BigInt(a.amount) - BigInt(a.storage_usage) * 10n ** 19n;
      return (free > 0n ? free : 0n).toString();
    });
    const direct = await Promise.all([NEAR_USDC, NEAR_USDT].map(c =>
      v.view<string>(c, "ft_balance_of", { account_id: dao }).then(b => ({ c, b: String(b) })).catch(() => ({ c, b: "0" }))));
    const inIntents = await v.view<string[]>(INTENTS_CONTRACT, "mt_batch_balance_of",
      { account_id: dao, token_ids: [`nep141:${NEAR_USDC}`, `nep141:${NEAR_USDT}`, "nep141:wrap.near"] })
      .catch(() => ["0", "0", "0"]);
    const tokens: PotBalance["tokens"] = [];
    for (const { c, b } of direct) {
      if (/^\d+$/.test(b) && BigInt(b) > 0n) tokens.push({ symbol: KNOWN_FT[c].symbol, amount: coinAmount(b, KNOWN_FT[c].decimals), contract: c, inIntents: false });
    }
    [NEAR_USDC, NEAR_USDT, "wrap.near"].forEach((c, i) => {
      const b = String(Array.isArray(inIntents) ? inIntents[i] ?? "0" : "0");
      if (/^\d+$/.test(b) && BigInt(b) > 0n) {
        tokens.push({ symbol: c === "wrap.near" ? "NEAR" : KNOWN_FT[c].symbol, amount: coinAmount(b, KNOWN_FT[c].decimals), contract: c, inIntents: true });
      }
    });
    return { near: coinAmount(near, 24), tokens };
  }

  /** A token's symbol and decimals: known ones by heart, others asked once. */
  private async ftInfo(contract: string): Promise<FtInfo | null> {
    if (KNOWN_FT[contract]) return KNOWN_FT[contract];
    if (this.ft.has(contract)) return this.ft.get(contract)!;
    const m = await this.views.view<{ symbol?: string; decimals?: number }>(contract, "ft_metadata").catch(() => null);
    const info = m && typeof m.symbol === "string" && Number.isInteger(m.decimals)
      ? { symbol: m.symbol.slice(0, 12), decimals: m.decimals! } : null;
    this.ft.set(contract, info);
    return info;
  }

  private async proposal(dao: string, policy: Policy, p: any): Promise<PotProposal | null> {
    if (!p || typeof p.id !== "number") return null;
    const kindName = typeof p.kind === "string" ? p.kind : Object.keys(p.kind ?? {})[0] ?? "Unknown";
    const label = policyLabel(kindName);
    let amount: string | null = null;
    let coin: string | null = null;
    let receiver: string | null = null;
    if (kindName === "Transfer") {
      const t = p.kind.Transfer ?? {};
      receiver = typeof t.receiver_id === "string" ? t.receiver_id : null;
      const info = await this.ftInfo(String(t.token_id ?? ""));
      if (info && /^\d+$/.test(String(t.amount))) {
        amount = coinAmount(String(t.amount), info.decimals);
        coin = info.symbol;
      }
    }
    const submittedNs = BigInt(String(p.submission_time ?? "0"));
    const expiresNs = submittedNs + BigInt(String(policy.proposal_period ?? "0"));
    let status = String(p.status) as ProposalStatus;
    if (status === "InProgress" && BigInt(this.now()) * NS_PER_MS > expiresNs) status = "Expired";
    const votes = { approve: 0, reject: 0, remove: 0 };
    const voters: Record<string, string> = {};
    for (const [who, vote] of Object.entries(p.votes ?? {})) {
      voters[who] = String(vote);
      if (vote === "Approve") votes.approve++;
      else if (vote === "Reject") votes.reject++;
      else if (vote === "Remove") votes.remove++;
    }
    // Still needed: for each voting role, its threshold less the approvals
    // already counted in that role; the smallest gap passes it.
    let needed: number | null = null;
    if (status === "InProgress") {
      for (const role of policy.roles) {
        if (!allows(role, label, "VoteApprove")) continue;
        const need = approvalsNeeded(policy, role, label);
        if (need === null) continue;
        const counted = Array.isArray(p.vote_counts?.[role.name]) ? Number(p.vote_counts[role.name][0]) : 0;
        const gap = Math.max(0, need - counted);
        needed = needed === null ? gap : Math.min(needed, gap);
      }
    }
    return {
      id: p.id, kind: kindName, description: plainDescription(p.description), amount, coin, receiver,
      proposer: String(p.proposer ?? ""), status, votes, voters, approvalsNeeded: needed,
      submitted: iso(submittedNs), expires: iso(expiresNs), url: `${TREZU}/${dao}/requests/${p.id}`,
    };
  }
}

// ---- Proposing a payout ----

export interface ProposeInput { dao: string; to: string; amount: string; coin?: string; note?: string }

export interface ProposeLink {
  ok: true;
  dao: string;
  /** Trezu's payment form with the recipient and token filled in. */
  url: string;
  /** What Trezu can't take from the URL, to type or paste there. */
  fill: { amount: string; coin: string; note: string };
  /** Where the members vote: the DAO's requests in Trezu. */
  votePage: string;
  /** One line for the chat once it's filed: "Proposing 120 USDC to
   *  caterer.near from the trip pot for catering. Vote: <votePage>". */
  text: string;
  /** Sputnik's own add_proposal call, for a wallet that signs it directly
   *  (attach `deposit` yoctoNEAR, the DAO's proposal bond). */
  call: { contract: string; method: "add_proposal"; args: unknown; deposit: string; gas: string };
}

/** The payout to propose, checked, as a Trezu link and a raw add_proposal. */
export function proposeLink(input: ProposeInput, bondYocto = "100000000000000000000000"): ProposeLink {
  const dao = input.dao.trim().toLowerCase();
  if (!SPUTNIK.test(dao)) throw new PotError(400, "A pot is a Sputnik DAO, like trip.sputnik-dao.near");
  const to = input.to.trim();
  if (!(NEAR_NAME.test(to) || NEAR_IMPLICIT_ACCOUNT.test(to))) throw new PotError(400, "Pay out to a NEAR account, like caterer.near");
  if (to === dao) throw new PotError(400, "That's the pot itself");
  const coin = (input.coin ?? "USDC").trim().replace(/^\$/, "").toUpperCase();
  if (!(coin in POT_COINS)) throw new PotError(400, "A pot pays out NEAR, USDC or USDT");
  const raw = input.amount.trim().replace(/[$,\s]/g, "");
  const decimals = coin === "NEAR" ? 24 : 6;
  let base: bigint;
  try {
    // More places than the coin has is a typo, not something to round.
    base = /^\d+(\.\d+)?$/.test(raw) && (raw.split(".")[1] ?? "").length <= decimals ? parseUnits(raw, decimals) : 0n;
  } catch {
    base = 0n;
  }
  if (base <= 0n) throw new PotError(400, "amount?");
  const amount = coinAmount(base.toString(), decimals);
  const note = String(input.note ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
  const contract = POT_COINS[coin];
  const q = new URLSearchParams({ address: to, ...(coin === "NEAR" ? { token: "NEAR", network: "near" } : { token: coin.toLowerCase(), network: contract }) });
  const name = dao.replace(/\.sputnik-dao\.near$/, "");
  return {
    ok: true, dao,
    url: `${TREZU}/${dao}/payments?${q}`,
    fill: { amount, coin, note },
    votePage: `${TREZU}/${dao}/requests`,
    text: `Proposing ${amount} ${coin} to ${to} from the ${name} pot${note ? ` for ${note}` : ""}. Vote: ${TREZU}/${dao}/requests`,
    call: {
      contract: dao, method: "add_proposal",
      args: { proposal: { description: note || `Pay ${amount} ${coin} to ${to}`,
        kind: { Transfer: { token_id: contract, receiver_id: to, amount: base.toString(), msg: null } } } },
      deposit: bondYocto, gas: "150000000000000",
    },
  };
}
