// Glyf's subscriptions in App Store Connect, step by step and safe to rerun
// (docs/APPS.md 5.21). Needs ASC_KEY_ID and ASC_ISSUER_ID (asc.mjs).
//   node setup.mjs structure       group, plans, names, levels, review notes,
//                                  availability, Apple's server notifications
//   node price-plan.mjs            decide every storefront's price
//   node setup.mjs prices [--dry]  set them (storefronts not yet priced)
//   SHOTS_DIR=… node setup.mjs shots   App Review's screenshots of the paywall
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { asc, all, pages } from './asc.mjs';
import { GROUP, PLANS, NOTIFICATIONS_URL, keyOf } from './plans.mjs';
import { rel, theApp, theGroup, theSubs } from './store.mjs';

const step = process.argv[2];
const dry = process.argv.includes('--dry');

async function structure() {
  const app = await theApp();
  const locale = app.attributes.primaryLocale || 'en-US';
  console.log('app', app.id, app.attributes.name, locale);
  const g = await theGroup(app, true);

  const glocs = await all(`/v1/subscriptionGroups/${g.id}/subscriptionGroupLocalizations?limit=50`);
  const gloc = glocs.find((l) => l.attributes.locale === locale);
  if (!gloc) {
    await asc('POST', '/v1/subscriptionGroupLocalizations', { data: { type: 'subscriptionGroupLocalizations',
      attributes: { locale, name: GROUP.displayName }, relationships: { subscriptionGroup: rel('subscriptionGroups', g.id) } } });
  } else if (gloc.attributes.name !== GROUP.displayName) {
    await asc('PATCH', `/v1/subscriptionGroupLocalizations/${gloc.id}`, { data: { type: 'subscriptionGroupLocalizations',
      id: gloc.id, attributes: { name: GROUP.displayName } } });
  }

  let subs = await theSubs(g);
  for (const p of PLANS) {
    if (subs[p.productId]) continue;
    // A product id can never be used again once created, even if deleted.
    subs[p.productId] = (await asc('POST', '/v1/subscriptions', { data: { type: 'subscriptions',
      attributes: { name: p.name, productId: p.productId, subscriptionPeriod: p.period, familySharable: false,
        reviewNote: p.reviewNote, groupLevel: p.level },
      relationships: { group: rel('subscriptionGroups', g.id) } } })).data;
    console.log('created', p.productId);
  }
  for (const p of PLANS) {
    const s = subs[p.productId], a = s.attributes, want = {};
    if (a.name !== p.name) want.name = p.name;
    if (a.reviewNote !== p.reviewNote) want.reviewNote = p.reviewNote;
    if (a.groupLevel !== p.level) want.groupLevel = p.level;
    if (Object.keys(want).length) {
      await asc('PATCH', `/v1/subscriptions/${s.id}`, { data: { type: 'subscriptions', id: s.id, attributes: want } });
    }
    const loc = (await all(`/v1/subscriptions/${s.id}/subscriptionLocalizations?limit=50`)).find((l) => l.attributes.locale === locale);
    if (!loc) {
      await asc('POST', '/v1/subscriptionLocalizations', { data: { type: 'subscriptionLocalizations',
        attributes: { locale, name: p.display, description: p.description }, relationships: { subscription: rel('subscriptions', s.id) } } });
    } else if (loc.attributes.name !== p.display || loc.attributes.description !== p.description) {
      await asc('PATCH', `/v1/subscriptionLocalizations/${loc.id}`, { data: { type: 'subscriptionLocalizations',
        id: loc.id, attributes: { name: p.display, description: p.description } } });
    }
  }

  const territories = (await all('/v1/territories?limit=200')).map((t) => t.id);
  for (const p of PLANS) {
    const s = subs[p.productId];
    const cur = await asc('GET', `/v1/subscriptions/${s.id}/subscriptionAvailability`, null, { raw: true });
    if (cur.status === 200 && cur.json?.data) continue;
    await asc('POST', '/v1/subscriptionAvailabilities', { data: { type: 'subscriptionAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: { subscription: rel('subscriptions', s.id),
        availableTerritories: { data: territories.map((id) => ({ type: 'territories', id })) } } } });
    console.log('available in', territories.length, 'storefronts:', p.productId);
  }

  const a = app.attributes;
  if (a.subscriptionStatusUrl !== NOTIFICATIONS_URL || a.subscriptionStatusUrlVersion !== 'V2'
      || a.subscriptionStatusUrlForSandbox !== NOTIFICATIONS_URL || a.subscriptionStatusUrlVersionForSandbox !== 'V2') {
    await asc('PATCH', `/v1/apps/${app.id}`, { data: { type: 'apps', id: app.id, attributes: {
      subscriptionStatusUrl: NOTIFICATIONS_URL, subscriptionStatusUrlVersion: 'V2',
      subscriptionStatusUrlForSandbox: NOTIFICATIONS_URL, subscriptionStatusUrlVersionForSandbox: 'V2' } } });
    console.log('server notifications (V2, production and sandbox) →', NOTIFICATIONS_URL);
  }
  subs = await theSubs(g);
  for (const p of PLANS) console.log(p.productId, subs[p.productId].attributes.state);
}

async function prices() {
  const plan = JSON.parse(fs.readFileSync(process.env.PRICE_PLAN || 'price-plan.json', 'utf8'));
  const subs = await theSubs(await theGroup(await theApp()));
  for (const p of PLANS) {
    const s = subs[p.productId];
    const rows = Object.entries(plan[keyOf(p.productId)]).map(([territory, r]) => ({ territory, ...r }));
    const have = await pages(`/v1/subscriptions/${s.id}/prices?include=territory&limit=200`);
    const priced = new Set(have.data.map((x) => x.relationships?.territory?.data?.id).filter(Boolean));
    const todo = rows.filter((r) => !priced.has(r.territory));
    if (dry) { console.log(p.productId, `${rows.length} storefronts, ${todo.length} to price`); continue; }
    let done = 0; const failed = [];
    const queue = [...todo];
    await Promise.all(Array.from({ length: 4 }, async () => {
      while (queue.length) {
        const r = queue.shift();
        try {
          await asc('POST', '/v1/subscriptionPrices', { data: { type: 'subscriptionPrices',
            attributes: { startDate: null, preserveCurrentPrice: false },
            relationships: { subscription: rel('subscriptions', s.id), subscriptionPricePoint: rel('subscriptionPricePoints', r.point) } } });
          done++;
        } catch (e) { failed.push(`${r.territory}: ${e.message.split('\n').slice(1).join(' ') || e.message}`); }
      }
    }));
    console.log(p.productId, `priced ${done} (${priced.size} already were)${failed.length ? `; ${failed.length} failed, rerun:\n   ` + failed.slice(0, 8).join('\n   ') : ''}`);
  }
}

async function shots() {
  const dir = process.env.SHOTS_DIR;
  if (!dir) throw new Error('set SHOTS_DIR to the folder with glyf-paywall-monthly.png and glyf-paywall-yearly.png');
  const subs = await theSubs(await theGroup(await theApp()));
  for (const p of PLANS) {
    const s = subs[p.productId];
    const cur = await asc('GET', `/v1/subscriptions/${s.id}/appStoreReviewScreenshot`, null, { raw: true });
    if (cur.status === 200 && cur.json?.data) {
      if (cur.json.data.attributes?.assetDeliveryState?.state !== 'FAILED' && !process.argv.includes('--replace')) {
        console.log(p.productId, 'has its screenshot'); continue;
      }
      await asc('DELETE', `/v1/subscriptionAppStoreReviewScreenshots/${cur.json.data.id}`);
    }
    const buf = fs.readFileSync(path.join(dir, p.shot));
    const made = (await asc('POST', '/v1/subscriptionAppStoreReviewScreenshots', { data: { type: 'subscriptionAppStoreReviewScreenshots',
      attributes: { fileName: p.shot, fileSize: buf.length }, relationships: { subscription: rel('subscriptions', s.id) } } })).data;
    for (const op of made.attributes.uploadOperations) {
      const headers = Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value]));
      const res = await fetch(op.url, { method: op.method, headers, body: buf.subarray(op.offset, op.offset + op.length) });
      if (!res.ok) throw new Error(`screenshot upload ${res.status}`);
    }
    await asc('PATCH', `/v1/subscriptionAppStoreReviewScreenshots/${made.id}`, { data: { type: 'subscriptionAppStoreReviewScreenshots',
      id: made.id, attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(buf).digest('hex') } } });
    console.log(p.productId, 'screenshot uploaded', p.shot);
  }
}

const steps = { structure, prices, shots };
if (!steps[step]) { console.log('steps:', Object.keys(steps).join(', ')); process.exit(1); }
await steps[step]();
