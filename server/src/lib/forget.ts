import type { KV } from "./store.js";

/**
 * What the server keeps under a phone's device id, gone (Delete account).
 *
 * The device id is the phone's own random id (shared settings `deviceId`).
 * Glyfs someone made, the hub entries they published, what they installed,
 * their OAuth connections and the days the phone was seen are all filed
 * under it rather than under the account, so deleting the account has to
 * name the phone too.
 *
 *   userglyfs        id → { ownerId: deviceId, ... }
 *   hub              id → { ownerId: deviceId, ... }
 *   accounts         deviceId → { displayName }
 *   devices          deviceId → { days }
 *   installs         `${deviceId}:${glyfId}`
 *   skill-installs-by `${deviceId}:${glyfId}`
 *   connections      `${deviceId}:${provider}` (OAuth tokens)
 *   oauth_pending    state → { deviceId, ... }
 *
 * The per-day event counts (`telemetry`, `${day}:${event}`) carry no device
 * or account and stay. Returns how many rows went, for the log.
 */
export function forgetDevices(kv: KV, deviceIds: readonly string[]): number {
  const ids = new Set(deviceIds.filter(d => typeof d === "string" && d.length > 0));
  if (ids.size === 0) return 0;
  let removed = 0;
  const drop = (collection: string, key: string) => {
    if (kv.get(collection, key) === undefined) return;
    kv.del(collection, key);
    removed++;
  };

  for (const collection of ["userglyfs", "hub"]) {
    for (const { id, value } of kv.list<{ ownerId?: string }>(collection)) {
      if (value?.ownerId && ids.has(value.ownerId)) drop(collection, id);
    }
  }
  for (const d of ids) {
    drop("accounts", d);
    drop("devices", d);
  }
  for (const collection of ["installs", "skill-installs-by", "connections"]) {
    for (const { id } of kv.list(collection)) {
      if ([...ids].some(d => id.startsWith(`${d}:`))) drop(collection, id);
    }
  }
  for (const { id, value } of kv.list<{ deviceId?: string }>("oauth_pending")) {
    if (value?.deviceId && ids.has(value.deviceId)) drop("oauth_pending", id);
  }
  return removed;
}
