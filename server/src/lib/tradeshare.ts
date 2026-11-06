import { randomBytes } from "node:crypto";
import type { KV } from "./store.js";

/**
 * A trade someone made with Glyf, shared into a chat as a link
 * (routes/tradeshare.ts). The link's page says what the trade was and opens
 * the same trade in Glyf for whoever taps Copy, who quotes and signs it with
 * their own wallet.
 *
 * A share holds the keyboard's words for the trade (TradeIntent.query: kind,
 * tokens, amount, prices, chain), the one-line summary, and where to see it
 * (a transaction hash or a Flash order id). Never a name, an email or a
 * recipient: the account id is kept only so a share has an owner.
 */

export interface TradeShare {
  user: string;
  query: Record<string, string>;
  summary: string;
  chainId?: number;
  txHash?: string;
  orderId?: string;
  createdAt: number;
}

const COLLECTION = "tradeshares";

/** Links live in chats for a while; a month is long enough to copy one. */
export const SHARE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export function createShare(kv: KV, share: Omit<TradeShare, "createdAt">, now = Date.now()): string {
  const id = randomBytes(9).toString("base64url"); // 12 chars, 72 bits: not enumerable
  kv.put<TradeShare>(COLLECTION, id, { ...share, createdAt: now });
  sweep(kv, now);
  return id;
}

export function getShare(kv: KV, id: string, now = Date.now()): TradeShare | undefined {
  if (!/^[\w-]{12}$/.test(id)) return undefined;
  const share = kv.get<TradeShare>(COLLECTION, id);
  if (!share || now - share.createdAt > SHARE_TTL_MS) return undefined;
  return share;
}

/** Old shares go when a new one is made, so the collection stays small. */
function sweep(kv: KV, now: number): void {
  for (const { id, value } of kv.list<TradeShare>(COLLECTION)) {
    if (now - value.createdAt > SHARE_TTL_MS) kv.del(COLLECTION, id);
  }
}

/** Which venue carries a kind: Uniswap swaps, Definitive's Flash for the rest. */
export function venueOf(kind: string | undefined): string {
  return !kind || kind === "swap" ? "Uniswap" : "Flash by Definitive";
}

/** The deep link Copy opens: the keyboard's own hand-off (openApp in
 *  GlyfKeyboardViewController), keys sorted, marked as copied. */
export function copyLink(query: Record<string, string>): string {
  const q: Record<string, string> = { ...query, copied: "1" };
  const inner = "trade?" + Object.keys(q).sort()
    .map(k => `${encodeURIComponent(k)}=${encodeURIComponent(q[k])}`).join("&");
  return `glyf://open?path=${encodeURIComponent(inner)}`;
}

const STYLE = `
  :root { color-scheme: light dark; --bg:#f2f2f7; --card:#fff; --ink:#1c1c1e; --soft:#8e8e93; --line:rgba(60,60,67,.12);
          --blue:#007aff; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#000; --card:#1c1c1e; --ink:#f2f2f7; --soft:#98989f; --line:rgba(84,84,88,.5); --blue:#0a84ff; }
  }
  * { box-sizing:border-box; margin:0 }
  html, body { background:var(--bg); color:var(--ink); }
  body { font:17px/1.35 -apple-system, "SF Pro Text", Inter, system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  main { max-width:480px; margin:0 auto; padding:28px 16px 40px; display:grid; gap:18px; }
  .brand { display:flex; align-items:center; gap:10px; color:var(--soft); font-size:15px; font-weight:600; }
  .mark { width:30px; height:30px; border-radius:9px; background:var(--ink); color:var(--bg); display:grid; place-items:center;
          font-weight:800; font-size:17px; letter-spacing:-.04em; }
  .kicker { color:var(--soft); font-size:13px; font-weight:600; text-transform:uppercase; letter-spacing:.04em; margin-bottom:6px; }
  h1 { font-size:28px; font-weight:700; letter-spacing:-.02em; line-height:1.15; text-wrap:balance; }
  .sub { color:var(--soft); font-size:15px; margin-top:6px; }
  .card { background:var(--card); border-radius:16px; overflow:hidden; }
  .row { display:flex; align-items:center; justify-content:space-between; gap:12px; padding:14px 16px; min-height:52px; }
  .row + .row { border-top:.5px solid var(--line); }
  .row span { color:var(--soft); font-size:15px; }
  .row b { font-weight:600; font-size:16px; text-align:right; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .row a { color:var(--blue); font-weight:600; font-size:16px; text-decoration:none; }
  a.button { appearance:none; border:0; width:100%; height:52px; border-radius:14px; background:var(--blue); color:#fff;
           font:600 17px -apple-system, system-ui, sans-serif; display:grid; place-items:center; text-decoration:none; }
  a.button:focus-visible, a.get:focus-visible { outline:3px solid color-mix(in srgb, var(--blue) 45%, transparent); outline-offset:2px; }
  a.get { justify-self:center; color:var(--blue); font-size:15px; font-weight:600; text-decoration:none; padding:6px 10px; }
`;

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const CHAINS: Record<number, { name: string; explorer: string; site: string }> = {
  1: { name: "Ethereum", explorer: "https://etherscan.io", site: "Etherscan" },
  8453: { name: "Base", explorer: "https://basescan.org", site: "Basescan" },
  42161: { name: "Arbitrum", explorer: "https://arbiscan.io", site: "Arbiscan" },
  10: { name: "Optimism", explorer: "https://optimistic.etherscan.io", site: "Etherscan" },
  137: { name: "Polygon", explorer: "https://polygonscan.com", site: "Polygonscan" },
  130: { name: "Unichain", explorer: "https://uniscan.xyz", site: "Uniscan" },
  84532: { name: "Base Sepolia", explorer: "https://sepolia.basescan.org", site: "Basescan" },
  11155111: { name: "Sepolia", explorer: "https://sepolia.etherscan.io", site: "Etherscan" },
};

export function chainInfo(chainId: number | undefined) {
  return chainId === undefined ? undefined : CHAINS[chainId];
}

function when(ms: number): string {
  const d = new Date(ms);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${d.getUTCDate()} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${hh}:${mm} UTC`;
}

export function renderSharePage(share: TradeShare | null): string {
  const body = share ? (() => {
    const chain = chainInfo(share.chainId);
    const chainName = chain?.name ?? share.query.chain ?? "";
    const rows = [
      `<div class="row"><span>Venue</span><b>${esc(venueOf(share.query.kind))}</b></div>`,
      chainName ? `<div class="row"><span>Chain</span><b>${esc(chainName[0].toUpperCase() + chainName.slice(1))}</b></div>` : "",
      `<div class="row"><span>When</span><b>${esc(when(share.createdAt))}</b></div>`,
      share.txHash && chain
        ? `<div class="row"><span>Transaction</span><a href="${esc(`${chain.explorer}/tx/${share.txHash}`)}" rel="noopener noreferrer">View on ${esc(chain.site)}</a></div>`
        : "",
    ].filter(Boolean).join("\n    ");
    return `<header><p class="kicker">A trade made with Glyf</p><h1>${esc(share.summary)}</h1>
    <p class="sub">Copy it and Glyf opens the same trade, quoted again for you to check and sign with your own wallet.</p></header>
  <div class="card">
    ${rows}
  </div>
  <a class="button" id="copy" href="${esc(copyLink(share.query))}">Copy this trade</a>
  <a class="get" href="https://tryglyf.com" rel="noopener">Get Glyf</a>`;
  })()
    : `<header><h1>Trade not found</h1><p class="sub">This link is wrong or has run out.</p></header>
  <a class="get" href="https://tryglyf.com" rel="noopener">Get Glyf</a>`;
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex">
<title>${share ? esc(share.summary) + " · Glyf" : "Glyf"}</title>
<style>${STYLE}</style>
</head><body><main>
  <div class="brand"><span class="mark">g</span>Glyf</div>
  ${body}
</main></body></html>`;
}
