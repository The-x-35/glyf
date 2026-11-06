import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import { MemoryKV } from "../src/lib/store.js";
import { connectMessage, createJob } from "../src/lib/walletjobs.js";
import { walletJobRoutes } from "../src/routes/walletjobs.js";
import { signedInApp, testToken } from "./helpers.js";

const FROM = "0x2a1cB3CDA2d72e02d4BaF04C809145c0869975D7";
const HASH = "0x" + "ab".repeat(32);
const SIG = "0x" + "cd".repeat(65);
const swap = {
  kind: "run", wallet: "metamask", title: "Swap 0.05 ETH for USDC", from: FROM,
  steps: [
    { type: "tx", chainId: 8453, to: "0x2626664c2603336E57B271c5C0b26F421741e481", data: "0x5ae401dc", value: "50000000000000000", label: "Swap ETH for USDC" },
    { type: "typed", chainId: 8453, data: { domain: { chainId: 8453 }, types: {}, primaryType: "Order", message: {} }, label: "Sign the order" },
  ],
};

describe("wallet jobs", () => {
  it("makes a job, serves its page to the wallet, and hands the answers back to its owner only", async () => {
    const app = signedInApp(new MemoryKV());
    const made = await app.inject({ method: "POST", url: "/wallet-jobs", payload: swap });
    expect(made.statusCode).toBe(200);
    const { id, url } = made.json();
    expect(url).toMatch(new RegExp(`/w/${id}$`));

    // The wallet's browser has no session.
    const open = buildApp(new MemoryKV()); // a different store: proves nothing leaks across
    expect((await open.inject({ url: `/w/${id}/job` })).statusCode).toBe(404);

    const page = await app.inject({ url: `/w/${id}`, headers: { authorization: "" } });
    expect(page.statusCode).toBe(200);
    const csp = String(page.headers["content-security-policy"]);
    const nonce = /nonce-([^']+)'/.exec(csp)?.[1];
    expect(page.body).toContain(`<script nonce="${nonce}">`);
    expect(csp).toContain("connect-src 'self'");

    const job = (await app.inject({ url: `/w/${id}/job`, headers: { authorization: "" } })).json();
    expect(job).toMatchObject({ kind: "run", walletName: "MetaMask", from: FROM, status: "open" });
    expect(job.chains["8453"].name).toBe("Base");
    expect(job.user).toBeUndefined();

    const progress = await app.inject({ method: "POST", url: `/w/${id}/result`, headers: { authorization: "" },
      payload: { status: "open", results: [{ hash: HASH }] } });
    expect(progress.statusCode).toBe(200);
    const done = await app.inject({ method: "POST", url: `/w/${id}/result`, headers: { authorization: "" },
      payload: { status: "done", results: [{ hash: HASH }, { signature: SIG }], address: FROM } });
    expect(done.statusCode).toBe(200);
    const again = await app.inject({ method: "POST", url: `/w/${id}/result`, headers: { authorization: "" },
      payload: { status: "failed", results: [] } });
    expect(again.statusCode).toBe(409);

    const mine = (await app.inject({ url: `/wallet-jobs/${id}` })).json();
    expect(mine).toMatchObject({ status: "done", results: [{ hash: HASH }, { signature: SIG }], address: FROM });
    const theirs = await app.inject({ url: `/wallet-jobs/${id}`, headers: { authorization: `Bearer ${testToken("google:someone-else")}` } });
    expect(theirs.statusCode).toBe(404);
  });

  it("a connect job asks for one message signed, with the job's own code in it", async () => {
    const app = signedInApp(new MemoryKV());
    const { id } = (await app.inject({ method: "POST", url: "/wallet-jobs",
      payload: { kind: "connect", wallet: "phantom", title: "Connect Phantom" } })).json();
    const job = (await app.inject({ url: `/w/${id}/job`, headers: { authorization: "" } })).json();
    expect(job.steps).toEqual([{ type: "message", message: connectMessage(id), label: expect.any(String) }]);
    expect(job.walletName).toBe("Phantom");
  });

  it("refuses runs without steps, unknown chains, and too many answers", async () => {
    const app = signedInApp(new MemoryKV());
    expect((await app.inject({ method: "POST", url: "/wallet-jobs", payload: { ...swap, steps: [] } })).statusCode).toBe(400);
    expect((await app.inject({ method: "POST", url: "/wallet-jobs",
      payload: { ...swap, steps: [{ ...swap.steps[0], chainId: 999999 }] } })).statusCode).toBe(400);
    const { id } = (await app.inject({ method: "POST", url: "/wallet-jobs", payload: { ...swap, steps: [swap.steps[0]] } })).json();
    const tooMany = await app.inject({ method: "POST", url: `/w/${id}/result`, headers: { authorization: "" },
      payload: { status: "done", results: [{ hash: HASH }, { hash: HASH }] } });
    expect(tooMany.statusCode).toBe(400);
    expect((await app.inject({ url: "/w/not-a-real-id-at-all!/job", headers: { authorization: "" } })).statusCode).toBe(401);
  });

  it("reads a receipt only on the job's own chains", async () => {
    const kv = new MemoryKV();
    const calls: string[] = [];
    const fetchImpl = (async (url: string) => {
      calls.push(String(url));
      return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result: { status: "0x1" } }));
    }) as unknown as typeof fetch;
    const app = Fastify();
    walletJobRoutes(app, kv, { fetchImpl });
    const id = createJob(kv, { user: "u", kind: "run", wallet: "metamask", title: "t", from: FROM,
      steps: [{ type: "tx", chainId: 8453, to: FROM, label: "x" }] });
    expect((await app.inject({ url: `/w/${id}/receipt?chainId=8453&hash=${HASH}` })).json().status).toBe("success");
    expect((await app.inject({ url: `/w/${id}/receipt?chainId=1&hash=${HASH}` })).statusCode).toBe(400);
    expect(calls).toHaveLength(1);
  });
});
