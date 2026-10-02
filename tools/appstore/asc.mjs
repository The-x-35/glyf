// App Store Connect API client for Glyf's subscriptions (docs/APPS.md 5.21).
// Signs a short-lived ES256 token from the team key's .p8, which is never
// printed or kept anywhere else. Needs ASC_KEY_ID and ASC_ISSUER_ID (App
// Store Connect → Users and Access → Integrations → App Store Connect API);
// the key is read from ASC_KEY_PATH, else the usual private_keys folder.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER = process.env.ASC_ISSUER_ID;
if (!KEY_ID || !ISSUER) throw new Error('set ASC_KEY_ID and ASC_ISSUER_ID');
const KEY_PATH = process.env.ASC_KEY_PATH
  || [path.join(os.homedir(), '.appstoreconnect/private_keys'), path.join(os.homedir(), 'Downloads')]
    .map((dir) => path.join(dir, `AuthKey_${KEY_ID}.p8`)).find((p) => fs.existsSync(p));
if (!KEY_PATH) throw new Error(`AuthKey_${KEY_ID}.p8 not found: set ASC_KEY_PATH`);

const b64u = (b) => Buffer.from(b).toString('base64url');
let cached = { token: '', exp: 0 };
function token() {
  const now = Math.floor(Date.now() / 1000);
  if (cached.token && cached.exp - now > 120) return cached.token;
  const exp = now + 15 * 60;
  const data = `${b64u(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: ISSUER, iat: now, exp, aud: 'appstoreconnect-v1' }))}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: crypto.createPrivateKey(fs.readFileSync(KEY_PATH)), dsaEncoding: 'ieee-p1363' });
  cached = { token: `${data}.${b64u(sig)}`, exp };
  return cached.token;
}

export async function asc(method, url, body, { raw = false } = {}) {
  const full = url.startsWith('http') ? url : `https://api.appstoreconnect.apple.com${url}`;
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(full, {
      method,
      headers: { Authorization: `Bearer ${token()}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    // Rate limits and Apple's passing server errors (seen 2026-10-02) get retried.
    if ((res.status === 429 || res.status >= 500) && attempt < 4) { await new Promise((r) => setTimeout(r, 3000 * (attempt + 1))); continue; }
    const text = await res.text();
    const json = text ? JSON.parse(text) : null;
    if (raw) return { status: res.status, json };
    if (!res.ok) {
      const errs = (json?.errors || []).map((e) => `${e.code}: ${e.title} — ${e.detail}`).join('\n');
      throw new Error(`${method} ${url} → ${res.status}\n${errs}`);
    }
    return json;
  }
}

/** Every page of a listing: its data and what it included. */
export async function pages(first) {
  const data = [], included = [];
  let next = first;
  while (next) {
    const page = await asc('GET', next);
    data.push(...page.data);
    included.push(...(page.included || []));
    next = page.links?.next;
  }
  return { data, included };
}
export const all = async (first) => (await pages(first)).data;
