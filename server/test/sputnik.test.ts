import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { NEAR_RPC } from "../src/lib/names.js";
import { potSummary } from "../src/lib/paypage.js";
import {
  approvalsNeeded, coinAmount, membersOf, NEAR_USDC, nearViews, policyLabel, PotError, Pots, proposeLink, proposers, voteRule,
  type Policy,
} from "../src/lib/sputnik.js";
import { nearRoutes } from "../src/routes/near.js";

/** The group pot on Sputnik DAO (lib/sputnik.ts), against a stand-in NEAR
 *  RPC shaped like build.sputnik-dao.near's answers on 2026-11-13. */

const NOW = Date.parse("2026-11-13T00:00:00Z");
const DAO = "trip.sputnik-dao.near";
const NS = (iso: string) => (BigInt(Date.parse(iso)) * 1_000_000n).toString();
const WEEK_NS = "604800000000000";

const POLICY: Policy = {
  roles: [
    { name: "council", kind: { Group: ["ana.near", "ben.near", "cy.near"] },
      permissions: ["*:AddProposal", "*:VoteApprove", "*:VoteReject", "*:VoteRemove", "*:Finalize"],
      vote_policy: { transfer: { weight_kind: "RoleWeight", quorum: "0", threshold: [1, 2] } } },
    { name: "friends", kind: { Group: ["dee.near", "ana.near"] }, permissions: ["transfer:AddProposal"], vote_policy: {} },
    { name: "all", kind: "Everyone", permissions: ["vote:AddProposal"], vote_policy: {} },
  ],
  default_vote_policy: { weight_kind: "RoleWeight", quorum: "0", threshold: [1, 2] },
  proposal_bond: "100000000000000000000000",
  proposal_period: WEEK_NS,
};

const PROPOSALS = [
  { id: 4, proposer: "ana.near", description: "Cabin deposit <br>for the weekend", status: "Approved",
    kind: { Transfer: { token_id: NEAR_USDC, receiver_id: "cabins.near", amount: "300000000", msg: null } },
    vote_counts: { council: [2, 0, 0] }, votes: { "ana.near": "Approve", "ben.near": "Approve" }, submission_time: NS("2026-11-01T10:00:00Z") },
  { id: 5, proposer: "ben.near", description: "Caterer", status: "InProgress",
    kind: { Transfer: { token_id: "", receiver_id: "caterer.near", amount: "12500000000000000000000000", msg: null } },
    vote_counts: { council: [1, 0, 0] }, votes: { "ben.near": "Approve" }, submission_time: NS("2026-11-12T10:00:00Z") },
  { id: 6, proposer: "cy.near", description: "Gas money", status: "InProgress",
    kind: { Transfer: { token_id: "token.weird.near", receiver_id: "cy.near", amount: "5000", msg: null } },
    vote_counts: {}, votes: {}, submission_time: NS("2026-10-01T10:00:00Z") },
  { id: 7, proposer: "dee.near", description: "Add Dee", status: "InProgress", kind: { AddMemberToRole: { member_id: "dee.near", role: "council" } },
    vote_counts: {}, votes: { "ana.near": "Reject" }, submission_time: NS("2026-11-12T12:00:00Z") },
];

type Rpc = { account_id: string; method_name?: string; args?: any; request_type: string };

/** A NEAR RPC: views answered from a table, an unknown account as NEAR says it. */
function fakeRpc(opts: { down?: boolean; panicAvailable?: boolean; accounts?: string[]; available?: string } = {}) {
  const calls: Rpc[] = [];
  const accounts = opts.accounts ?? [DAO];
  const fetchImpl = (async (url: string, init: RequestInit = {}) => {
    if (String(url) !== NEAR_RPC) throw new Error(`unexpected ${url}`);
    if (opts.down) throw new Error("ECONNREFUSED");
    const { params } = JSON.parse(String(init.body));
    const args = params.args_base64 ? JSON.parse(Buffer.from(params.args_base64, "base64").toString()) : undefined;
    calls.push({ account_id: params.account_id, method_name: params.method_name, args, request_type: params.request_type });
    const reply = (json: unknown) => new Response(JSON.stringify({ jsonrpc: "2.0", id: "glyf", ...json as object }));
    const result = (value: unknown) => reply({ result: { result: [...Buffer.from(JSON.stringify(value))], logs: [], block_height: 1 } });
    const known = accounts.includes(params.account_id) || ["intents.near", NEAR_USDC, "usdt.tether-token.near", "token.weird.near"].includes(params.account_id);
    if (!known) return reply({ error: { name: "HANDLER_ERROR", cause: { name: "UNKNOWN_ACCOUNT" } } });
    if (params.request_type === "view_account") {
      return reply({ result: { amount: "12000000000000000000000000", locked: "0", storage_usage: 100000 } });
    }
    const m = params.method_name;
    if (params.account_id === DAO) {
      if (m === "get_config") return result({ name: "trip", purpose: "Lisbon trip, Nov 2026", metadata: "" });
      if (m === "get_policy") return result(POLICY);
      if (m === "get_last_proposal_id") return result(8);
      if (m === "get_available_amount") {
        if (opts.panicAvailable) return reply({ result: { error: "wasm execution failed: attempt to subtract with overflow", logs: [] } });
        return result(opts.available ?? "42500000000000000000000000");
      }
      if (m === "get_proposals") return result(PROPOSALS.filter(p => p.id >= args.from_index && p.id < args.from_index + args.limit));
    }
    if (params.account_id === NEAR_USDC && m === "ft_balance_of") return result(args.account_id === DAO ? "120500000" : "0");
    if (params.account_id === "usdt.tether-token.near" && m === "ft_balance_of") return result("0");
    if (params.account_id === "intents.near" && m === "mt_batch_balance_of") return result(["20000000", "0", "0"]);
    if (params.account_id === "token.weird.near" && m === "ft_metadata") return result({ symbol: "WEIRD", decimals: 3 });
    return reply({ result: { error: `MethodNotFound ${m}`, logs: [] } });
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

describe("Sputnik policies", () => {
  it("names a proposal's policy label the contract's way", () => {
    expect(policyLabel("Transfer")).toBe("transfer");
    expect(policyLabel("FunctionCall")).toBe("call");
    expect(policyLabel("AddMemberToRole")).toBe("add_member_to_role");
    expect(policyLabel("ChangePolicyAddOrUpdateRole")).toBe("policy_add_or_update_role");
    expect(policyLabel("ChangeConfig")).toBe("config");
    expect(policyLabel("SetStakingContract")).toBe("set_vote_token");
  });

  it("counts approvals as VotePolicy::to_weight does: a ratio plus one, a fixed weight, and the quorum", () => {
    const role = POLICY.roles[0];
    expect(approvalsNeeded(POLICY, role, "transfer")).toBe(2);         // 1/2 of 3 → 1 + 1
    const fixed = { ...POLICY, roles: [{ ...role, vote_policy: { transfer: { weight_kind: "RoleWeight", quorum: "0", threshold: "1" } } }] };
    expect(approvalsNeeded(fixed, fixed.roles[0], "transfer")).toBe(1);
    const quorum = { ...POLICY, roles: [{ ...role, vote_policy: { transfer: { weight_kind: "RoleWeight", quorum: "3", threshold: [1, 10] as [number, number] } } }] };
    expect(approvalsNeeded(quorum, quorum.roles[0], "transfer")).toBe(3);
    const big = { ...POLICY, roles: [{ ...role, kind: { Group: ["a", "b", "c", "d", "e"] }, vote_policy: { transfer: { threshold: [23, 100] as [number, number] } } }] };
    expect(approvalsNeeded(big, big.roles[0], "transfer")).toBe(2);   // build.sputnik-dao.near's council
    expect(approvalsNeeded(POLICY, POLICY.roles[2], "transfer")).toBeNull();
    const tokens = { ...POLICY, roles: [{ ...role, vote_policy: { transfer: { weight_kind: "TokenWeight", threshold: [1, 2] as [number, number] } } }] };
    expect(approvalsNeeded(tokens, tokens.roles[0], "transfer")).toBeNull();
  });

  it("finds who's in, who votes a payout, and who may propose one", () => {
    expect(membersOf(POLICY)).toEqual(["ana.near", "ben.near", "cy.near", "dee.near"]);
    expect(voteRule(POLICY, "transfer")).toEqual({ role: "council", approvals: 2, of: 3, words: "2 of 3" });
    expect(proposers(POLICY)).toEqual(["ana.near", "ben.near", "cy.near", "dee.near"]);
    const open = { ...POLICY, roles: [...POLICY.roles, { name: "anyone", kind: "Everyone", permissions: ["transfer:AddProposal"], vote_policy: {} }] };
    expect(proposers(open)).toBe("everyone");
  });

  it("writes coin amounts plainly", () => {
    expect(coinAmount("12500000000000000000000000", 24)).toBe("12.5");
    expect(coinAmount("120500000", 6)).toBe("120.5");
    expect(coinAmount("1234567891", 9)).toBe("1.234567");
    expect(coinAmount("0", 24)).toBe("0");
  });
});

describe("a pot, read from NEAR", () => {
  it("shows the balance, members, payout rule and latest proposals with their votes", async () => {
    const rpc = fakeRpc();
    const pot = await new Pots({ fetchImpl: rpc.fetchImpl, now: () => NOW }).pot("Trip.sputnik-dao.near");
    expect(pot).toMatchObject({
      ok: true, dao: DAO, name: "trip", purpose: "Lisbon trip, Nov 2026",
      balance: { near: "42.5", tokens: [
        { symbol: "USDC", amount: "120.5", contract: NEAR_USDC, inIntents: false },
        { symbol: "USDC", amount: "20", contract: NEAR_USDC, inIntents: true },
      ] },
      members: ["ana.near", "ben.near", "cy.near", "dee.near"], memberCount: 4,
      threshold: { approvals: 2, of: 3, words: "2 of 3" }, bond: "0.1", votingDays: 7, lastProposalId: 8, open: 2,
      text: "The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open",
      links: { trezu: `https://trezu.app/${DAO}/dashboard`, propose: `https://trezu.app/${DAO}/payments` },
    });
    expect(pot.proposals.map(p => p.id)).toEqual([7, 6, 5, 4]);
    const [add, weird, caterer, cabin] = pot.proposals;
    expect(caterer).toMatchObject({ kind: "Transfer", amount: "12.5", coin: "NEAR", receiver: "caterer.near", status: "InProgress",
      votes: { approve: 1, reject: 0, remove: 0 }, voters: { "ben.near": "Approve" }, approvalsNeeded: 1,
      submitted: "2026-11-12T10:00:00.000Z", expires: "2026-11-19T10:00:00.000Z", url: `https://trezu.app/${DAO}/requests/5` });
    expect(cabin).toMatchObject({ amount: "300", coin: "USDC", status: "Approved", approvalsNeeded: null, description: "Cabin deposit \nfor the weekend" });
    // Open past its week: expired. An unknown token's decimals are asked of it.
    expect(weird).toMatchObject({ status: "Expired", amount: "5", coin: "WEIRD" });
    expect(add).toMatchObject({ kind: "AddMemberToRole", amount: null, approvalsNeeded: 2, votes: { reject: 1 } });
    const asked = rpc.calls.find(c => c.method_name === "get_proposals")!;
    expect(asked.args).toEqual({ from_index: 0, limit: 10 });
  });

  it("falls back to the account balance when get_available_amount panics, and keeps a pot 30 seconds", async () => {
    const rpc = fakeRpc({ panicAvailable: true });
    const pots = new Pots({ fetchImpl: rpc.fetchImpl, now: () => NOW });
    const pot = await pots.pot(DAO);
    expect(pot.balance.near).toBe("11");   // 12 NEAR less 100,000 bytes of storage
    const before = rpc.calls.length;
    await pots.pot(DAO);
    expect(rpc.calls.length).toBe(before);
  });

  it("groups a big balance's thousands in the line put in the chat, as the pay page does", async () => {
    const rpc = fakeRpc({ available: "7811321498000000000000000000" });
    const pot = await new Pots({ fetchImpl: rpc.fetchImpl, now: () => NOW }).pot(DAO);
    expect(pot.balance.near).toBe("7811.321498");
    expect(pot.text).toMatch(/^The trip pot holds 7,811\.32 NEAR · 140\.5 USDC\. /);
  });

  it("says plainly when there's no such DAO, it isn't one, or NEAR is down", async () => {
    const fail = (dao: string, opts = {}) => new Pots({ fetchImpl: fakeRpc(opts).fetchImpl, now: () => NOW }).pot(dao)
      .then(() => null, (err: PotError) => [err.status, err.message]);
    expect(await fail("nope.sputnik-dao.near")).toEqual([404, "No Sputnik DAO nope.sputnik-dao.near"]);
    expect(await fail("alice.near")).toEqual([400, "A pot is a Sputnik DAO, like trip.sputnik-dao.near"]);
    expect(await fail(DAO, { down: true })).toEqual([502, "NEAR didn't answer. Try again in a moment"]);
  });

  it("asks NEAR_RPC_URL when it's set", async () => {
    const urls: string[] = [];
    const views = nearViews((async (url: string) => { urls.push(String(url)); throw new Error("x"); }) as unknown as typeof fetch,
      "https://rpc.example.org");
    await views.view(DAO, "get_config").catch(() => undefined);
    expect(urls).toEqual(["https://rpc.example.org"]);
  });

  it("says a pot's holdings and members in a line each for the pay page", () => {
    expect(potSummary({ near: "42.5", tokens: [{ symbol: "USDC", amount: "120.5" }, { symbol: "USDC", amount: "20" }] },
      ["ana.near", "ben.near", "cy.near", "dee.near"], 4))
      .toEqual({ holds: "Holds 42.5 NEAR · 140.5 USDC", members: "4 members: ana.near, ben.near, cy.near and 1 more" });
    expect(potSummary({ near: "7811.321498", tokens: [] }, ["a.near", "b.near"], 2))
      .toEqual({ holds: "Holds 7,811.32 NEAR", members: "2 members: a.near and b.near" });
  });
});

describe("proposing a payout", () => {
  it("links Trezu's payment form with the recipient and token, and gives the add_proposal call", () => {
    const usdc = proposeLink({ dao: DAO, to: "caterer.near", amount: "$120", note: "catering" });
    expect(usdc).toMatchObject({
      ok: true, dao: DAO,
      url: `https://trezu.app/${DAO}/payments?address=caterer.near&token=usdc&network=${NEAR_USDC}`,
      fill: { amount: "120", coin: "USDC", note: "catering" },
      votePage: `https://trezu.app/${DAO}/requests`,
      text: `Proposing 120 USDC to caterer.near from the trip pot for catering. Vote: https://trezu.app/${DAO}/requests`,
      call: { contract: DAO, method: "add_proposal", deposit: "100000000000000000000000",
        args: { proposal: { description: "catering", kind: { Transfer: { token_id: NEAR_USDC, receiver_id: "caterer.near", amount: "120000000", msg: null } } } } },
    });
    const near = proposeLink({ dao: DAO, to: "bob.near", amount: "2.5", coin: "near" });
    expect(near.url).toBe(`https://trezu.app/${DAO}/payments?address=bob.near&token=NEAR&network=near`);
    expect((near.call.args as any).proposal).toEqual({ description: "Pay 2.5 NEAR to bob.near",
      kind: { Transfer: { token_id: "", receiver_id: "bob.near", amount: "2500000000000000000000000", msg: null } } });
  });

  it("refuses a payout it can't propose", () => {
    const fail = (input: Parameters<typeof proposeLink>[0]) => { try { proposeLink(input); return ""; } catch (err) { return (err as Error).message; } };
    expect(fail({ dao: "alice.near", to: "bob.near", amount: "1" })).toBe("A pot is a Sputnik DAO, like trip.sputnik-dao.near");
    expect(fail({ dao: DAO, to: "the caterer", amount: "1" })).toBe("Pay out to a NEAR account, like caterer.near");
    expect(fail({ dao: DAO, to: DAO, amount: "1" })).toBe("That's the pot itself");
    expect(fail({ dao: DAO, to: "bob.near", amount: "1", coin: "DOGE" })).toBe("A pot pays out NEAR, USDC or USDT");
    expect(fail({ dao: DAO, to: "bob.near", amount: "0" })).toBe("amount?");
    expect(fail({ dao: DAO, to: "bob.near", amount: "1.0000001" })).toBe("amount?");
  });
});

describe("GET /near/pot and GET /near/pot/propose-link", () => {
  function app(opts: Parameters<typeof fakeRpc>[0] = {}) {
    const rpc = fakeRpc(opts);
    const a = Fastify();
    nearRoutes(a, { fetchImpl: rpc.fetchImpl, jwt: () => "", now: () => NOW });
    return { app: a, rpc };
  }

  it("answers the pot and a propose link with the DAO's own bond and rule", async () => {
    const { app: a } = app();
    const pot = await a.inject({ method: "GET", url: `/near/pot?dao=${DAO}` });
    expect(pot.statusCode).toBe(200);
    expect(pot.json()).toMatchObject({ ok: true, dao: DAO, balance: { near: "42.5" }, threshold: { words: "2 of 3" } });
    const link = await a.inject({ method: "GET",
      url: `/near/pot/propose-link?dao=${DAO}&to=caterer.near&amount=120&coin=USDC&note=${encodeURIComponent("catering")}` });
    expect(link.statusCode).toBe(200);
    expect(link.json()).toMatchObject({ ok: true, bond: "0.1", threshold: { words: "2 of 3" },
      proposers: ["ana.near", "ben.near", "cy.near", "dee.near"], fill: { amount: "120", coin: "USDC" },
      call: { deposit: "100000000000000000000000" } });
  });

  it("is a 400, 404 or 502 in words", async () => {
    const { app: a, rpc } = app();
    const get = async (url: string) => { const r = await a.inject({ method: "GET", url }); return [r.statusCode, r.json().error]; };
    expect(await get("/near/pot")).toEqual([400, "dao?"]);
    expect(await get("/near/pot?dao=nope.sputnik-dao.near")).toEqual([404, "No Sputnik DAO nope.sputnik-dao.near"]);
    expect(await get(`/near/pot/propose-link?dao=${DAO}&amount=5`)).toEqual([400, "to?"]);
    const before = rpc.calls.length;
    expect(await get(`/near/pot/propose-link?dao=${DAO}&to=the%20caterer&amount=5`)).toEqual([400, "Pay out to a NEAR account, like caterer.near"]);
    expect(rpc.calls.length).toBe(before);
    const down = app({ down: true }).app;
    expect((await down.inject({ method: "GET", url: `/near/pot?dao=${DAO}` })).statusCode).toBe(502);
  });
});
