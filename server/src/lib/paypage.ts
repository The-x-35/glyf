import QRCode from "qrcode";
import { NEAR_CHAINS, type Deposit } from "./nearintents.js";
import {
  amountWords, daoName, PAY_WITH, shortRecipient, type PayRequest, type Tally,
} from "./payrequests.js";

/**
 * GET /pay/<id>: one self-contained page (no outside script, font or
 * image), phone first, light and dark. Its one script carries the page's
 * nonce; the server's CSP allows nothing else.
 */

const escape = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/** JSON safe inside a <script> element. */
const scriptJson = (v: unknown) => JSON.stringify(v).replace(/</g, "\\u003c").replace(/\u2028|\u2029/g, " ");

/** What the QR holds: a payment URI where wallets read one (BIP-21 for
 *  Bitcoin and Zcash, Solana Pay), the bare deposit address elsewhere. */
export function depositUri(chain: string, depositAddress: string, amount: string, mint?: string): string {
  if (chain === "bitcoin") return `bitcoin:${depositAddress}?amount=${amount}`;
  if (chain === "zcash") return `zcash:${depositAddress}?amount=${amount}`;
  if (chain === "solana") return `solana:${depositAddress}?amount=${amount}${mint ? `&spl-token=${mint}` : ""}`;
  return depositAddress;
}

/** The QR as an SVG data URI, drawn here (nothing is fetched to draw it). */
export async function qrDataUri(text: string): Promise<string> {
  const svg = await QRCode.toString(text, { type: "svg", margin: 1, errorCorrectionLevel: "M",
    color: { dark: "#000000", light: "#ffffff" } });
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;
}

/** MetaMask's EIP-681 link for an EVM deposit, which opens the transfer
 *  filled in on a phone with MetaMask. */
export function metamaskLink(d: Deposit): string | null {
  if (d.kind === "erc20") {
    return `https://metamask.app.link/send/${d.token}@${d.chainId}/transfer?address=${d.depositAddress}&uint256=${d.amountBase}`;
  }
  if (d.kind === "native") return `https://metamask.app.link/send/${d.depositAddress}@${d.chainId}?value=${d.amountBase}`;
  return null;
}

/** The headline: "Dinner · $22.50 to alice.near". */
export function headline(r: PayRequest): string {
  const money = `${amountWords(r.amount, r.coin)}${r.each ? " each" : ""} to ${shortRecipient(r.to)}`;
  return r.note ? `${r.note} · ${money}` : money;
}

const PLACEHOLDER: Record<string, string> = {
  evm: "0x…", solana: "Your Solana address", bitcoin: "bc1…", zcash: "t1…", near: "you.near",
};

export function renderPayPage(r: PayRequest, tally: Tally, nonce: string): string {
  const chain = NEAR_CHAINS[r.chain];
  const money = amountWords(r.amount, r.coin);
  const options = PAY_WITH.filter(o => !(o.coin === r.coin && o.chain === r.chain)).map(o => ({
    id: o.id, label: o.label, chain: o.chain, chainName: NEAR_CHAINS[o.chain].name,
    placeholder: NEAR_CHAINS[o.chain].kind === "evm" ? PLACEHOLDER.evm : PLACEHOLDER[o.chain] ?? "",
  }));
  const data = { id: r.id, to: shortRecipient(r.to), full: tally.full, count: tally.count, paid: tally.paid, options };
  const title = r.note ? `${r.note} · ${money}` : `${money} pay request`;
  const dots = tally.count && tally.count <= 12
    ? `<span class="dots" aria-hidden="true">${Array.from({ length: tally.count }, (_, i) =>
      `<i class="${i < tally.paid ? "on" : ""}"></i>`).join("")}</span>` : "";
  const pills = options.map((o, i) =>
    `<label class="opt"><input type="radio" name="with" value="${escape(o.id)}"${i === 0 ? " checked" : ""}><span>${escape(o.label)}</span></label>`)
    .join("");

  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex">
<title>${escape(title)}</title>
<meta property="og:title" content="${escape(title)}">
<meta property="og:description" content="Pay with any coin · NEAR Intents">
<style>
  :root { color-scheme: light dark; --bg:#f5f5f7; --card:#fff; --ink:#1d1d1f; --soft:#6e6e73; --line:rgba(0,0,0,.08);
          --field:#f5f5f7; --accent:#7c5cff; --on-ink:#fff; --bad:#d70015; --good:#248a3d; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#000; --card:#1c1c1e; --ink:#f5f5f7; --soft:#a1a1a6; --line:rgba(255,255,255,.12);
            --field:#2c2c2e; --on-ink:#000; --bad:#ff6961; --good:#30d158; }
  }
  * { box-sizing:border-box; margin:0 }
  html { -webkit-text-size-adjust:100% }
  body { background:var(--bg); color:var(--ink); min-height:100vh;
         font:16px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif; }
  main { max-width:460px; margin:0 auto; padding:max(36px, env(safe-area-inset-top)) 16px 32px; }
  .kicker { font-size:13px; font-weight:600; color:var(--soft); text-transform:uppercase; letter-spacing:.06em; }
  .amount { margin-top:10px; font-size:52px; font-weight:700; letter-spacing:-.04em; line-height:1; }
  .amount small { font-size:20px; font-weight:600; letter-spacing:-.01em; color:var(--soft); margin-left:4px; }
  .line { margin-top:12px; font-size:17px; font-weight:500; letter-spacing:-.01em; overflow-wrap:anywhere; }
  .pot { margin-top:6px; color:var(--soft); font-size:15px; overflow-wrap:anywhere; }
  .tally { margin-top:14px; display:flex; align-items:center; gap:10px; font-size:15px; font-weight:600; }
  .tally:empty { display:none }
  .dots { display:flex; gap:5px; }
  .dots i { width:10px; height:10px; border-radius:50%; background:var(--line); }
  .dots i.on { background:var(--accent); }
  .card { margin-top:24px; padding:20px 18px; border-radius:22px; background:var(--card); border:1px solid var(--line); }
  h2 { font-size:15px; font-weight:600; color:var(--soft); }
  .opts { margin-top:12px; display:flex; flex-wrap:wrap; gap:8px; }
  .opt input { position:absolute; opacity:0; pointer-events:none; }
  .opt span { display:inline-block; padding:9px 14px; border-radius:999px; background:var(--field); font-size:15px;
              font-weight:500; border:1.5px solid transparent; cursor:pointer; user-select:none; }
  .opt input:checked + span { border-color:var(--accent); background:transparent; }
  .opt input:focus-visible + span { outline:2px solid var(--accent); outline-offset:2px; }
  .field { display:block; margin-top:18px; }
  .field span { font-size:15px; font-weight:600; color:var(--soft); }
  .field input { display:block; width:100%; margin-top:8px; padding:13px 14px; border-radius:14px; border:1px solid var(--line);
                 background:var(--field); color:var(--ink); font:inherit; font-size:16px; }
  .field input:focus { outline:2px solid var(--accent); outline-offset:-1px; }
  .pill { display:flex; align-items:center; justify-content:center; width:100%; margin-top:18px; padding:15px 20px; border:0;
          border-radius:999px; background:var(--ink); color:var(--on-ink); font:inherit; font-size:17px; font-weight:600;
          text-decoration:none; cursor:pointer; }
  .pill[disabled] { opacity:.45; cursor:default; }
  .ghost { display:block; margin:14px auto 0; background:none; border:0; color:var(--soft); font:inherit; font-size:15px;
           font-weight:500; cursor:pointer; }
  .err { margin-top:12px; color:var(--bad); font-size:15px; }
  .err:empty { display:none }
  .qr { display:block; width:220px; height:220px; margin:0 auto; border-radius:14px; background:#fff; padding:8px; }
  .send { margin-top:16px; text-align:center; font-size:17px; }
  .gets { margin-top:4px; text-align:center; color:var(--soft); font-size:14px; overflow-wrap:anywhere; }
  .addr { margin-top:16px; display:flex; align-items:center; gap:8px; padding:10px 10px 10px 14px; border-radius:14px; background:var(--field); }
  .addr code { flex:1; min-width:0; font:14px/1.35 ui-monospace, "SF Mono", Menlo, monospace; overflow-wrap:anywhere; }
  .copy { flex:none; padding:8px 14px; border-radius:999px; border:0; background:var(--ink); color:var(--on-ink);
          font:inherit; font-size:14px; font-weight:600; cursor:pointer; }
  .memo { margin-top:10px; font-size:14px; color:var(--soft); }
  .status { margin-top:18px; display:flex; align-items:center; justify-content:center; gap:10px; font-weight:600; text-align:center; }
  .status.good { color:var(--good); }
  .status.bad { color:var(--bad); }
  .spin { width:14px; height:14px; border-radius:50%; border:2px solid var(--line); border-top-color:var(--accent);
          animation:spin .9s linear infinite; flex:none; }
  .status.good .spin, .status.bad .spin { display:none; }
  @keyframes spin { to { transform:rotate(360deg) } }
  @media (prefers-reduced-motion: reduce) { .spin { animation:none } }
  .status a { color:inherit; }
  .until { margin-top:6px; text-align:center; font-size:13px; color:var(--soft); }
  .done { margin-top:24px; padding:22px 18px; border-radius:22px; background:var(--card); border:1px solid var(--line);
          text-align:center; font-size:17px; font-weight:600; }
  [hidden] { display:none !important; }
  footer { margin-top:28px; font-size:13px; color:var(--soft); text-align:center; }
  footer a { color:inherit; font-weight:600; text-decoration:none; }
  footer .dot { display:inline-block; width:.3em; height:.3em; border-radius:50%; background:var(--accent); transform:translateY(-.6em); margin-left:.1em; }
</style></head>
<body><main>
  <p class="kicker">${r.pot ? "Shared pot" : "Pay request"}</p>
  <p class="amount">${escape(money)}${r.each ? "<small>each</small>" : ""}</p>
  <p class="line">${escape(headline(r))}</p>
  ${r.pot ? `<p class="pot">Into the ${escape(daoName(r.to))} DAO treasury · shared pot</p>`
    : `<p class="pot">Paid as ${escape(r.coin)} on ${escape(chain?.name ?? r.chain)}</p>`}
  <p class="tally" id="tally">${tally.words ? `${dots}<span id="tallyWords">${escape(tally.words)}</span>` : ""}</p>

  <p class="done" id="full"${tally.full ? "" : " hidden"}>Everyone's paid</p>

  <form class="card" id="pay" novalidate${tally.full ? " hidden" : ""}>
    <h2>Pay with</h2>
    <div class="opts" role="radiogroup" aria-label="Pay with">${pills}</div>
    <label class="field"><span>Refund address</span>
      <input id="refund" name="refundTo" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" required></label>
    <button class="pill" id="go" type="submit">Get deposit address</button>
    <p class="err" id="err" role="alert"></p>
  </form>

  <section class="card" id="deposit" hidden aria-live="polite">
    <img class="qr" id="qr" alt="Deposit address QR code">
    <p class="send">Send exactly <b id="sendAmount"></b></p>
    <p class="gets" id="gets"></p>
    <div class="addr"><code id="addr"></code><button class="copy" id="copy" type="button">Copy</button></div>
    <p class="memo" id="memo" hidden></p>
    <a class="pill" id="wallet" hidden rel="noopener">Open in MetaMask</a>
    <p class="status" id="status"><span class="spin"></span><span id="statusWords">Waiting for your deposit</span></p>
    <p class="until" id="until"></p>
    <button class="ghost" id="again" type="button">Pay with something else</button>
  </section>

  <footer>Through NEAR Intents · Made with <a href="https://tryglyf.com">glyf<span class="dot"></span></a></footer>
</main>
<script id="data" type="application/json">${scriptJson(data)}</script>
<script nonce="${escape(nonce)}">
(function () {
  var D = JSON.parse(document.getElementById("data").textContent);
  var $ = function (id) { return document.getElementById(id); };
  var form = $("pay"), refund = $("refund"), go = $("go"), err = $("err");
  var card = $("deposit"), timer = null, current = null;
  var KEY = "glyf-pay-" + D.id;
  function store(v) { try { v ? localStorage.setItem(KEY, JSON.stringify(v)) : localStorage.removeItem(KEY); } catch (e) {} }
  function stored() { try { return JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) { return null; } }
  function pick() { var c = form.querySelector("input[name=with]:checked"); return c ? c.value : ""; }
  function option(id) { for (var i = 0; i < D.options.length; i++) if (D.options[i].id === id) return D.options[i]; return null; }
  function placeholder() { var o = option(pick()); refund.placeholder = o ? o.placeholder : ""; }
  form.addEventListener("change", function (e) { if (e.target.name === "with") { placeholder(); err.textContent = ""; } });
  placeholder();

  function tally(t) {
    if (!t) return;
    var box = $("tally");
    if (!t.words) { box.textContent = ""; return; }
    var html = "";
    if (t.count && t.count <= 12) {
      html = '<span class="dots" aria-hidden="true">';
      for (var i = 0; i < t.count; i++) html += '<i class="' + (i < t.paid ? "on" : "") + '"></i>';
      html += "</span>";
    }
    box.innerHTML = html + '<span id="tallyWords"></span>';
    $("tallyWords").textContent = t.words;
    if (t.full && !current) { form.hidden = true; $("full").hidden = false; }
  }

  var WORDS = { PENDING_DEPOSIT: "Waiting for your deposit", INCOMPLETE_DEPOSIT: "Got part of it. Send the rest",
    PROCESSING: "Paying " + D.to + "…", SUCCESS: "Paid", REFUNDED: "Refunded to you", FAILED: "Didn't go through" };
  function status(s) {
    var line = $("status");
    line.className = "status" + (s.status === "SUCCESS" ? " good" : s.status === "FAILED" || s.status === "REFUNDED" ? " bad" : "");
    var words = $("statusWords");
    words.textContent = WORDS[s.status] || WORDS.PENDING_DEPOSIT;
    if (s.status === "SUCCESS" && s.destinationTx && /^https:\\/\\//.test(s.destinationTx.url)) {
      var a = document.createElement("a");
      a.href = s.destinationTx.url; a.rel = "noopener"; a.textContent = " · View";
      words.appendChild(a);
    }
    if (s.done) { $("until").textContent = ""; $("wallet").hidden = true; }
  }

  function poll() {
    if (!current) return;
    var q = "?deposit=" + encodeURIComponent(current.depositAddress) + (current.depositMemo ? "&memo=" + encodeURIComponent(current.depositMemo) : "");
    fetch("/pay/" + D.id + "/status" + q, { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (s) {
      if (!s || !s.ok) return;
      status(s); tally(s.tally);
      if (s.done) { clearInterval(timer); timer = null; store(null); }
    }).catch(function () {});
  }

  function show(q) {
    current = q;
    $("qr").src = q.qr;
    $("sendAmount").textContent = q.amount + " " + q.coin + " on " + q.chainName;
    $("gets").textContent = D.to + " gets " + q.gets;
    $("addr").textContent = q.depositAddress;
    var memo = $("memo");
    memo.hidden = !q.depositMemo; memo.textContent = q.depositMemo ? "Memo: " + q.depositMemo : "";
    var w = $("wallet");
    if (q.wallet) { w.href = q.wallet; w.hidden = false; } else { w.hidden = true; }
    $("until").textContent = q.deadline ? "Address works until " + new Date(q.deadline).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "";
    status({ status: "PENDING_DEPOSIT" });
    form.hidden = true; card.hidden = false;
    clearInterval(timer); timer = setInterval(poll, 5000); poll();
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    err.textContent = "";
    var to = refund.value.trim();
    if (!to) { err.textContent = "Add your refund address"; refund.focus(); return; }
    go.disabled = true; go.textContent = "Getting a quote…";
    fetch("/pay/" + D.id + "/quote", { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ with: pick(), refundTo: to }) })
      .then(function (r) { return r.json().catch(function () { return { ok: false }; }); })
      .then(function (q) {
        if (!q || !q.ok) { err.textContent = (q && q.error) || "Couldn't get a quote. Try again"; return; }
        store(q); show(q);
      })
      .catch(function () { err.textContent = "Couldn't reach Glyf. Try again"; })
      .then(function () { go.disabled = false; go.textContent = "Get deposit address"; });
  });

  $("copy").addEventListener("click", function () {
    if (!current) return;
    var b = this;
    try { navigator.clipboard.writeText(current.depositAddress).then(function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1500); }); } catch (e) {}
  });
  $("again").addEventListener("click", function () {
    clearInterval(timer); timer = null; current = null; store(null);
    card.hidden = true; form.hidden = D.full; $("full").hidden = !D.full;
  });

  var saved = stored();
  if (saved && saved.depositAddress && (!saved.deadline || Date.parse(saved.deadline) > Date.now() - 6 * 3600 * 1000)) show(saved);
  fetch("/pay/" + D.id + "/status", { cache: "no-store" }).then(function (r) { return r.json(); })
    .then(function (s) { if (s && s.ok) { D.full = s.tally.full; tally(s.tally); } }).catch(function () {});
})();
</script>
</body></html>`;
}

export function notFoundPage(): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Link not found</title><style>:root{color-scheme:light dark}body{margin:0;display:grid;place-items:center;min-height:100vh;
font:17px -apple-system,Inter,system-ui,sans-serif;background:#f5f5f7;color:#1d1d1f}@media (prefers-color-scheme:dark){body{background:#000;color:#f5f5f7}}</style>
</head><body><p>This pay link doesn't exist</p></body></html>`;
}
