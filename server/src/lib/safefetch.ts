/**
 * Fetching a URL someone else chose (a pasted link for url.unfurl), without
 * letting it reach inside the server's own network.
 *
 * Every hop is checked: the scheme (http or https), the port (the web's
 * usual ones), and the address the name actually resolves to at connect
 * time, which shuts out DNS rebinding between a check and the request.
 * Loopback, private, link-local (cloud metadata at 169.254.169.254),
 * carrier-grade NAT, multicast, reserved and IPv6 local ranges are refused,
 * as are IPv4 addresses hidden inside IPv6 (mapped, NAT64, 6to4). Redirects
 * are followed by hand, a few at most, each one checked the same way.
 */
import { lookup as dnsLookup } from "node:dns";
import { BlockList, isIP, type LookupFunction } from "node:net";
import { request as httpRequest, type IncomingMessage } from "node:http";
import { request as httpsRequest } from "node:https";
import { createBrotliDecompress, createGunzip, createInflate } from "node:zlib";
import type { Readable } from "node:stream";

export class BlockedUrlError extends Error {}

const blocked = new BlockList();
for (const [net, bits] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8],
  ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24],
  ["192.88.99.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
] as const) blocked.addSubnet(net, bits, "ipv4");
for (const [net, bits] of [
  ["::", 128], ["::1", 128], ["::", 96], ["100::", 64], ["2001:db8::", 32],
  ["fc00::", 7], ["fe80::", 10], ["fec0::", 10], ["ff00::", 8],
] as const) blocked.addSubnet(net, bits, "ipv6");

/** The 32 bits at `offset` (in 16-bit groups) of a full IPv6 address, as v4. */
function v4At(groups: number[], offset: number): string {
  const hi = groups[offset], lo = groups[offset + 1];
  return `${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}`;
}

/** An IPv6 address as eight numbers, or null. */
function v6Groups(address: string): number[] | null {
  let a = address.toLowerCase().split("%")[0];
  // A dotted tail (::ffff:1.2.3.4) becomes two hex groups.
  const dotted = a.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
  if (dotted) {
    const p = dotted[2].split(".").map(Number);
    a = `${dotted[1]}${((p[0] << 8) | p[1]).toString(16)}:${((p[2] << 8) | p[3]).toString(16)}`;
  }
  const [head, tail] = a.includes("::") ? a.split("::") : [a, undefined];
  const h = head ? head.split(":") : [];
  const t = tail !== undefined ? (tail ? tail.split(":") : []) : [];
  const fill = tail !== undefined ? 8 - h.length - t.length : 0;
  const all = [...h, ...Array(Math.max(fill, 0)).fill("0"), ...t];
  if (all.length !== 8) return null;
  const nums = all.map(g => parseInt(g, 16));
  return nums.every(n => Number.isInteger(n) && n >= 0 && n <= 0xffff) ? nums : null;
}

/** True for an address the server must never be sent to. */
export function isBlockedAddress(address: string): boolean {
  const kind = isIP(address.split("%")[0]);
  if (kind === 4) return blocked.check(address, "ipv4");
  if (kind !== 6) return true;
  const g = v6Groups(address);
  if (!g) return true;
  const zeros = (n: number) => g.slice(0, n).every(x => x === 0);
  // IPv4-mapped ::ffff:a.b.c.d and IPv4-translated ::ffff:0:a.b.c.d
  if (zeros(5) && g[5] === 0xffff) return isBlockedAddress(v4At(g, 6));
  if (zeros(4) && g[4] === 0xffff && g[5] === 0) return isBlockedAddress(v4At(g, 6));
  // NAT64 64:ff9b::/96 and 64:ff9b:1::/48
  if (g[0] === 0x64 && g[1] === 0xff9b) return isBlockedAddress(v4At(g, 6));
  // 6to4 2002:a.b.c.d::/48
  if (g[0] === 0x2002) return isBlockedAddress(v4At(g, 1));
  // Teredo 2001:0::/32 carries the client's address inverted; refuse it all.
  if (g[0] === 0x2001 && g[1] === 0) return true;
  return blocked.check(address.split("%")[0], "ipv6");
}

const ALLOWED_PORTS = new Set(["", "80", "443", "8080", "8443"]);

/** Throws BlockedUrlError for a URL that may not be fetched at all. */
export function checkUrl(raw: string | URL): URL {
  let u: URL;
  try { u = new URL(raw); } catch { throw new BlockedUrlError("not a URL"); }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new BlockedUrlError("only http and https");
  if (u.username || u.password) throw new BlockedUrlError("no credentials in links");
  if (!ALLOWED_PORTS.has(u.port)) throw new BlockedUrlError("port not allowed");
  const host = u.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".internal")
      || host.endsWith(".local") || !host.includes(".") && !isIP(host)) {
    throw new BlockedUrlError("internal host");
  }
  if (isIP(host) && isBlockedAddress(host)) throw new BlockedUrlError("internal address");
  return u;
}

/** A DNS lookup that refuses names resolving anywhere internal. Used at
 *  connect time, so the address checked is the address dialled. */
export const guardedLookup: LookupFunction = (hostname, options, callback) => {
  dnsLookup(hostname, { ...options, all: true }, (err, addresses) => {
    if (err) return (callback as (e: Error | null, a: string, f?: number) => void)(err, "", 4);
    const list = addresses as unknown as { address: string; family: number }[];
    if (!list.length || list.some(a => isBlockedAddress(a.address))) {
      const e = new BlockedUrlError("internal address");
      return (callback as (e: Error | null, a: string, f?: number) => void)(e, "", 4);
    }
    if ((options as { all?: boolean }).all) {
      return (callback as unknown as (e: null, a: typeof list) => void)(null, list);
    }
    (callback as (e: null, a: string, f: number) => void)(null, list[0].address, list[0].family);
  });
};

export interface SafeFetchOptions {
  timeoutMs: number;
  headers?: Record<string, string>;
  maxBytes?: number;
  maxRedirects?: number;
}

export interface SafeResponse {
  status: number;
  url: string;
  contentType: string;
  text: string;
}

function once(u: URL, opts: SafeFetchOptions, signal: AbortSignal): Promise<IncomingMessage> {
  return new Promise((resolve, reject) => {
    const req = (u.protocol === "https:" ? httpsRequest : httpRequest)(u, {
      method: "GET",
      headers: { "accept-encoding": "gzip, deflate, br", ...opts.headers },
      lookup: guardedLookup,
      signal,
    }, resolve);
    req.on("error", reject);
    req.end();
  });
}

function decoded(res: IncomingMessage): Readable {
  switch ((res.headers["content-encoding"] ?? "").toLowerCase()) {
    case "gzip": return res.pipe(createGunzip());
    case "deflate": return res.pipe(createInflate());
    case "br": return res.pipe(createBrotliDecompress());
    default: return res;
  }
}

/** GET a URL a user supplied, as text, at most `maxBytes` of it. */
export async function safeFetchText(raw: string, opts: SafeFetchOptions): Promise<SafeResponse> {
  const signal = AbortSignal.timeout(opts.timeoutMs);
  const maxBytes = opts.maxBytes ?? 256 * 1024;
  let u = checkUrl(raw);
  for (let hop = 0; ; hop++) {
    const res = await once(u, opts, signal);
    const status = res.statusCode ?? 0;
    const location = res.headers.location;
    if (status >= 300 && status < 400 && location) {
      res.resume();
      if (hop >= (opts.maxRedirects ?? 4)) throw new BlockedUrlError("too many redirects");
      u = checkUrl(new URL(location, u));
      continue;
    }
    const chunks: Buffer[] = [];
    let size = 0;
    const body = decoded(res);
    try {
      for await (const chunk of body) {
        const b = chunk as Buffer;
        chunks.push(b);
        size += b.length;
        if (size >= maxBytes) break;
      }
    } finally {
      res.destroy();
    }
    return {
      status,
      url: u.toString(),
      contentType: String(res.headers["content-type"] ?? ""),
      text: Buffer.concat(chunks).subarray(0, maxBytes).toString("utf8"),
    };
  }
}
