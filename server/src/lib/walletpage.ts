/**
 * The page a wallet's browser opens for a Glyf job (routes/walletjobs.ts).
 *
 * It reads the job, asks the wallet's provider (window.ethereum) for each
 * signature in turn, waits for each transaction to land before the next,
 * and sends what the wallet answered back under the job's id. The only
 * script is this one, under a per-response nonce; it talks to nothing but
 * this server.
 */

const STYLE = `
  :root { color-scheme: light dark; --bg:#f2f2f7; --card:#fff; --ink:#1c1c1e; --soft:#8e8e93; --line:rgba(60,60,67,.12);
          --blue:#007aff; --green:#34c759; --red:#ff3b30; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#000; --card:#1c1c1e; --ink:#f2f2f7; --soft:#98989f; --line:rgba(84,84,88,.5); --blue:#0a84ff; --green:#30d158; --red:#ff453a; }
  }
  * { box-sizing:border-box; margin:0 }
  html, body { background:var(--bg); color:var(--ink); }
  body { font:17px/1.35 -apple-system, "SF Pro Text", Inter, system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  main { max-width:480px; margin:0 auto; padding:28px 16px 40px; display:grid; gap:18px; }
  .brand { display:flex; align-items:center; gap:10px; color:var(--soft); font-size:15px; font-weight:600; }
  .mark { width:30px; height:30px; border-radius:9px; background:var(--ink); color:var(--bg); display:grid; place-items:center;
          font-weight:800; font-size:17px; letter-spacing:-.04em; }
  h1 { font-size:28px; font-weight:700; letter-spacing:-.02em; line-height:1.15; text-wrap:balance; }
  .sub { color:var(--soft); font-size:15px; margin-top:6px; }
  .card { background:var(--card); border-radius:16px; overflow:hidden; }
  .row { display:flex; align-items:center; gap:12px; padding:14px 16px; min-height:52px; }
  .row + .row { border-top:.5px solid var(--line); }
  .dot { flex:none; width:22px; height:22px; border-radius:11px; border:2px solid var(--line); display:grid; place-items:center;
         font-size:12px; font-weight:800; color:#fff; }
  .row.active .dot { border-color:var(--blue); border-top-color:transparent; animation:spin .8s linear infinite; }
  .row.done .dot { background:var(--green); border-color:var(--green); }
  .row.done .dot::after { content:"✓"; }
  .row.failed .dot::after { content:"!"; }
  .row.failed .dot { background:var(--red); border-color:var(--red); }
  .row .what { flex:1; min-width:0; }
  .row .what b { display:block; font-weight:600; font-size:16px; }
  .row .what i { display:block; font-style:normal; color:var(--soft); font-size:13.5px; margin-top:1px;
                 overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  button, a.button { appearance:none; border:0; width:100%; height:52px; border-radius:14px; background:var(--blue); color:#fff;
           font:600 17px -apple-system, system-ui, sans-serif; display:grid; place-items:center; text-decoration:none; cursor:pointer; }
  button:disabled { opacity:.45; }
  button:focus-visible, a.button:focus-visible { outline:3px solid color-mix(in srgb, var(--blue) 45%, transparent); outline-offset:2px; }
  .note { text-align:center; color:var(--soft); font-size:14px; min-height:20px; }
  .note.bad { color:var(--red); font-weight:600; }
  @keyframes spin { to { transform:rotate(360deg) } }
  @media (prefers-reduced-motion: reduce) { .row.active .dot { animation:none; border-top-color:var(--blue); } }
`;

const SCRIPT = String.raw`
(() => {
  const id = location.pathname.split('/')[2];
  const $ = (s) => document.querySelector(s);
  const steps = $('#steps'), go = $('#go'), note = $('#note'), title = $('#title'), sub = $('#sub');
  let job = null, results = [];

  const short = (a) => a ? a.slice(0, 6) + '…' + a.slice(-4) : '';
  const say = (t, bad) => { note.textContent = t || ''; note.className = 'note' + (bad ? ' bad' : ''); };
  const post = (body) => fetch('/w/' + id + '/result', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body) }).catch(() => {});
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function provider() {
    const want = job && job.wallet;
    if (want === 'phantom' && window.phantom && window.phantom.ethereum) return window.phantom.ethereum;
    return window.ethereum || null;
  }

  function draw() {
    steps.innerHTML = '';
    job.steps.forEach((s, i) => {
      const row = document.createElement('div');
      const state = i < results.length ? 'done' : '';
      row.className = 'row ' + state;
      row.id = 'step' + i;
      const chain = s.chainId && job.chains[s.chainId];
      row.innerHTML = '<span class="dot"></span><span class="what"><b></b><i></i></span>';
      row.querySelector('b').textContent = s.label;
      row.querySelector('i').textContent = s.type === 'tx' ? (chain ? chain.name : '') + ' · transaction'
        : s.type === 'typed' ? (chain ? chain.name : '') + ' · signature, no fee' : 'Signature, no fee';
      steps.appendChild(row);
    });
  }
  const mark = (i, state) => { const r = $('#step' + i); if (r) r.className = 'row ' + state; };

  async function ensureChain(p, chainId) {
    const hex = '0x' + chainId.toString(16);
    const now = await p.request({ method: 'eth_chainId' });
    if (String(now).toLowerCase() === hex) return;
    try {
      await p.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: hex }] });
    } catch (e) {
      if (e && (e.code === 4902 || /unrecognized|not added|unknown chain/i.test(e.message || ''))) {
        const c = job.chains[chainId];
        await p.request({ method: 'wallet_addEthereumChain', params: [{ chainId: hex, chainName: c.name,
          nativeCurrency: { name: c.native, symbol: c.native, decimals: 18 }, rpcUrls: [c.rpc],
          ...(c.explorer ? { blockExplorerUrls: [c.explorer] } : {}) }] });
        await p.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: hex }] });
      } else throw e;
    }
  }

  async function landed(chainId, hash) {
    for (let i = 0; i < 150; i++) {
      await sleep(2000);
      try {
        const r = await (await fetch('/w/' + id + '/receipt?chainId=' + chainId + '&hash=' + hash)).json();
        if (r.status === 'success') return true;
        if (r.status === 'reverted') return false;
      } catch (_) {}
    }
    throw new Error('The network is taking too long. Check it in Glyf');
  }

  const toHex = (n) => '0x' + BigInt(n).toString(16);
  const utf8Hex = (s) => '0x' + Array.from(new TextEncoder().encode(s), (b) => b.toString(16).padStart(2, '0')).join('');

  async function run() {
    const p = provider();
    if (!p) { say('Open this page in ' + (job.walletName || 'your wallet') + '’s browser', true); return; }
    go.disabled = true;
    say('');
    let i = results.length;
    try {
      const accounts = await p.request({ method: 'eth_requestAccounts' });
      let account = accounts && accounts[0];
      if (job.from) {
        const match = (accounts || []).find((a) => a.toLowerCase() === job.from.toLowerCase());
        if (!match) throw Object.assign(new Error('This is ' + short(account) + '. Switch to ' + short(job.from) + ' in ' + job.walletName + ' and tap again'), { keep: true });
        account = match;
      }
      for (; i < job.steps.length; i++) {
        const s = job.steps[i];
        mark(i, 'active');
        if (s.type === 'tx') {
          await ensureChain(p, s.chainId);
          say('Confirm in ' + job.walletName);
          const tx = { from: account, to: s.to };
          if (s.data && s.data !== '0x') tx.data = s.data;
          if (s.value && s.value !== '0') tx.value = toHex(s.value);
          if (s.gas) tx.gas = toHex(s.gas);
          const hash = await p.request({ method: 'eth_sendTransaction', params: [tx] });
          results.push({ hash });
          post({ status: 'open', results });
          say('Waiting for ' + (job.chains[s.chainId] || {}).name + '…');
          if (!(await landed(s.chainId, hash))) throw new Error(s.label + ' reverted on chain');
        } else if (s.type === 'typed') {
          await ensureChain(p, s.chainId);
          say('Sign in ' + job.walletName);
          const signature = await p.request({ method: 'eth_signTypedData_v4', params: [account, JSON.stringify(s.data)] });
          results.push({ signature });
          post({ status: 'open', results });
        } else {
          say('Sign in ' + job.walletName);
          const signature = await p.request({ method: 'personal_sign', params: [utf8Hex(s.message), account] });
          results.push({ signature });
        }
        mark(i, 'done');
      }
      await post({ status: 'done', results, address: account });
      finished('Done', 'Go back to Glyf to finish.');
    } catch (e) {
      mark(i, 'failed');
      const cancelled = e && (e.code === 4001 || /reject|denied|cancel/i.test(e.message || ''));
      const why = cancelled ? 'You said no in ' + job.walletName : (e && e.message) || 'Something went wrong';
      if (e && e.keep) { mark(i, ''); say(why, true); go.disabled = false; return; }
      await post({ status: cancelled ? 'cancelled' : 'failed', results, error: why.slice(0, 280) });
      finished(cancelled ? 'Stopped' : 'That didn’t go through', why + '. Go back to Glyf.');
    }
  }

  function finished(head, line) {
    title.textContent = head;
    sub.textContent = line;
    say('');
    go.outerHTML = '<a class="button" id="back" href="glyf://evm-return">Back to Glyf</a>';
  }

  fetch('/w/' + id + '/job').then((r) => r.json()).then((j) => {
    if (!j.ok) { title.textContent = 'Link ran out'; sub.textContent = j.error; go.remove(); return; }
    job = j;
    results = j.results || [];
    title.textContent = j.title;
    sub.textContent = j.kind === 'connect' ? 'Connect ' + j.walletName + ' to Glyf. Nothing is sent and there’s no fee.'
      : 'From ' + short(j.from) + ' · ' + j.steps.length + (j.steps.length === 1 ? ' step' : ' steps') + ' in ' + j.walletName;
    if (j.status !== 'open') { draw(); finished('Already done', 'Go back to Glyf.'); return; }
    draw();
    go.textContent = j.kind === 'connect' ? 'Connect' : 'Confirm';
    go.disabled = false;
    go.addEventListener('click', run);
  }).catch(() => { title.textContent = 'No connection'; sub.textContent = 'Check the connection and reload.'; });
})();
`;

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function renderSignPage(info: { wallet: string } | null, nonce: string): string {
  const body = info
    ? `<header><h1 id="title">Loading…</h1><p class="sub" id="sub">Opening in ${esc(info.wallet)}</p></header>
  <div class="card" id="steps"></div>
  <button id="go" disabled>Confirm</button>
  <p class="note" id="note" role="status" aria-live="polite"></p>
  <script nonce="${nonce}">${SCRIPT}</script>`
    : `<header><h1>Link ran out</h1><p class="sub">Start again in Glyf.</p></header>`;
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex">
<title>Sign with Glyf</title>
<style>${STYLE}</style>
</head><body><main>
  <div class="brand"><span class="mark">g</span>Glyf</div>
  ${body}
</main></body></html>`;
}
