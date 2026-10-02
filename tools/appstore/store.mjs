// The app, its subscription group and its four subscriptions, found by name.
import { asc, all } from './asc.mjs';
import { BUNDLE_ID, GROUP } from './plans.mjs';

export const rel = (type, id) => ({ data: { type, id } });

export async function theApp() {
  const r = await asc('GET', `/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=bundleId,primaryLocale,name,subscriptionStatusUrl,subscriptionStatusUrlVersion,subscriptionStatusUrlForSandbox,subscriptionStatusUrlVersionForSandbox`);
  const app = r.data.find((a) => a.attributes.bundleId === BUNDLE_ID);
  if (!app) throw new Error(`no app with bundle id ${BUNDLE_ID}`);
  return app;
}

export async function theGroup(app, create = false) {
  const groups = await all(`/v1/apps/${app.id}/subscriptionGroups?limit=50`);
  let g = groups.find((x) => x.attributes.referenceName === GROUP.referenceName);
  if (!g && create) {
    g = (await asc('POST', '/v1/subscriptionGroups', { data: { type: 'subscriptionGroups',
      attributes: { referenceName: GROUP.referenceName }, relationships: { app: rel('apps', app.id) } } })).data;
    console.log('created group', g.id);
  }
  return g;
}

/** productId → subscription */
export async function theSubs(g) {
  const subs = await all(`/v1/subscriptionGroups/${g.id}/subscriptions?limit=50`);
  return Object.fromEntries(subs.map((s) => [s.attributes.productId, s]));
}
