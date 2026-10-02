// Decides every storefront's price for the four plans and writes it to
// price-plan.json (PRICE_PLAN to put it elsewhere); `setup.mjs prices` sets
// it. Rules (2026-10-02, Arpit: "whole nos only", "round to higher price only
// in round off, not lower"):
//  - monthly: Apple's conversion of the US price; a price with decimals
//    (SGD 2.98, PLN 9.99, BRL 12.90) → the next whole price up
//  - yearly: ten times that monthly price, so the paywall's "2 months free"
//    is true everywhere; where the storefront has no such price, the next
//    whole one up if it is within 1% (India ₹1,999 for ₹1,990), else the
//    whole one just under it (Brazil 129 for 130, Peru 229 for 230)
// Then it prints what each plan brings in a month in every storefront,
// against the most a subscriber can cost (docs/BACKEND.md 5.9).
import fs from 'node:fs';
import { asc, pages } from './asc.mjs';
import { PLANS, keyOf } from './plans.mjs';
import { theApp, theGroup, theSubs } from './store.mjs';

const OUT = process.env.PRICE_PLAN || 'price-plan.json';
const F = 'fields[subscriptionPricePoints]=customerPrice,proceeds,proceedsYear2,territory';
const whole = (v) => Number(v) === Math.round(Number(v));
const pt = (pp) => ({ point: pp.id, price: Number(pp.attributes.customerPrice), proceeds: Number(pp.attributes.proceeds) });

const g = await theGroup(await theApp());
if (!g) throw new Error('no subscription group yet: run setup.mjs structure first');
const subs = await theSubs(g);
const id = Object.fromEntries(PLANS.map((p) => [keyOf(p.productId), subs[p.productId]?.id]));
const usd = Object.fromEntries(PLANS.map((p) => [keyOf(p.productId), p.usd]));

async function converted(key) {
  let us = null, next = `/v1/subscriptions/${id[key]}/pricePoints?filter[territory]=USA&limit=200&${F}`;
  while (next && !us) { const pg = await asc('GET', next); us = pg.data.find((x) => Number(x.attributes.customerPrice) === usd[key]); next = pg.links?.next; }
  if (!us) throw new Error(`no US price point at $${usd[key]}`);
  const eq = await pages(`/v1/subscriptionPricePoints/${us.id}/equalizations?limit=200&include=territory&fields[territories]=currency&${F}`);
  const cur = Object.fromEntries(eq.included.filter((x) => x.type === 'territories').map((t) => [t.id, t.attributes.currency]));
  const rows = { USA: { currency: 'USD', ...pt(us) } };
  for (const pp of eq.data) { const t = pp.relationships.territory.data.id; rows[t] = { currency: cur[t], ...pt(pp) }; }
  return rows;
}

/** Every price point of these storefronts for one plan, cheapest first. */
async function ladders(key, territories) {
  const out = {}; const queue = [];
  for (let i = 0; i < territories.length; i += 10) queue.push(territories.slice(i, i + 10));
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (queue.length) {
      const chunk = queue.shift();
      const r = await pages(`/v1/subscriptions/${id[key]}/pricePoints?filter[territory]=${chunk.join(',')}&limit=200&include=territory&${F}`);
      for (const pp of r.data) (out[pp.relationships.territory.data.id] ??= []).push(pt(pp));
    }
  }));
  for (const t of Object.keys(out)) out[t].sort((a, b) => a.price - b.price);
  return out;
}

const plan = {};
for (const p of PLANS) plan[keyOf(p.productId)] = await converted(keyOf(p.productId));
for (const tier of ['plus', 'max']) {
  const m = plan[`${tier}.monthly`], y = plan[`${tier}.yearly`];
  const odd = Object.keys(m).filter((t) => !whole(m[t].price));
  const ml = odd.length ? await ladders(`${tier}.monthly`, odd) : {};
  for (const t of odd) {
    const up = (ml[t] || []).find((p) => whole(p.price) && p.price >= m[t].price);
    if (up) m[t] = { ...m[t], ...up, was: m[t].price };
    else console.log(`${tier} monthly ${t}: no whole price above ${m[t].price}`);
  }
  const off = Object.keys(y).filter((t) => y[t].price !== 10 * m[t].price);
  const yl = off.length ? await ladders(`${tier}.yearly`, off) : {};
  for (const t of off) {
    const target = 10 * m[t].price, ladder = yl[t] || [];
    const up = ladder.find((p) => whole(p.price) && p.price >= target);
    const down = [...ladder].reverse().find((p) => whole(p.price) && p.price < target);
    const pick = up && (up.price === target || up.price <= target * 1.01) ? up : down || up;
    if (pick && pick.price !== y[t].price) y[t] = { ...y[t], ...pick, was: y[t].price };
  }
}
fs.writeFileSync(OUT, JSON.stringify(plan, null, 1));

// What each plan brings in a month (Apple's proceeds: after its cut and the
// storefront's taxes), in dollars at today's rates, against the most a
// subscriber can cost: every cap spent every day.
const fx = (await (await fetch('https://open.er-api.com/v6/latest/USD')).json()).rates;
const worst = { plus: 0.48, max: 1.2 };
for (const tier of ['plus', 'max']) {
  const takes = Object.keys(plan[`${tier}.monthly`]).flatMap((t) => {
    const m = plan[`${tier}.monthly`][t], y = plan[`${tier}.yearly`][t], r = fx[m.currency];
    return r ? [{ t, kind: 'monthly', usd: m.proceeds / r }, { t, kind: 'yearly', usd: y.proceeds / 12 / r }] : [];
  }).sort((a, b) => a.usd - b.usd);
  const low = takes[0];
  console.log(`${tier}: lowest take ${low.t} ${low.kind} $${low.usd.toFixed(2)} a month against at most $${worst[tier].toFixed(2)} of AI (${Math.round(100 * (1 - worst[tier] / low.usd))}% left); ${takes.filter((x) => x.usd < worst[tier]).length} storefronts at a loss`);
}
for (const [key, rows] of Object.entries(plan)) {
  const moved = Object.entries(rows).filter(([, r]) => r.was !== undefined);
  console.log(`${key}: ${Object.keys(rows).length} storefronts, ${moved.length} away from Apple's conversion`);
}
console.log('written to', OUT);
