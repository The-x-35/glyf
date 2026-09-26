/**
 * Plus and Max bought through the App Store, checked here.
 *
 * StoreKit 2 hands the app each purchase as a JWS that Apple signed, and App
 * Store Server Notifications arrive signed the same way. Nothing the phone
 * says about a plan is taken on its word: the certificate chain in the JWS
 * header has to end in Apple Root CA - G3 (pinned by fingerprint), each
 * certificate has to be issued by the next and carry Apple's marker, and
 * the signature has to verify with the leaf's key. Node's own crypto does
 * all of it; no third party sits between Apple and the account.
 */
import { X509Certificate, verify } from "node:crypto";

/** Apple Root CA - G3, from Apple's PKI (and the macOS system roots). */
export const APPLE_ROOT_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

/** Apple's marker extensions, as DER: 1.2.840.113635.100.6.11.1 on the
 *  signing certificate, 1.2.840.113635.100.6.2.1 on the intermediate. */
const LEAF_MARKER = Buffer.from("060a2a864886f76364060b01", "hex");
const INTERMEDIATE_MARKER = Buffer.from("060a2a864886f76364060201", "hex");

/** The subscriptions in the "Glyf Pro" group, and the plan each one buys. */
export const APPLE_PRODUCTS: Readonly<Record<string, "plus" | "max">> = {
  "com.arpit.glyf.plus.monthly": "plus",
  "com.arpit.glyf.plus.yearly": "plus",
  "com.arpit.glyf.max.monthly": "max",
  "com.arpit.glyf.max.yearly": "max",
};

/** The fields of a signed transaction this server reads. */
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
}

export class AppleSignatureError extends Error {}

export interface VerifyOptions {
  /** StoreKit testing in Xcode signs locally, with no Apple chain: accepted
   *  only when this is set, which the server does outside production. */
  allowXcode?: boolean;
  /** For tests with their own root; Apple's everywhere else. */
  rootFingerprint?: string;
  now?: Date;
}

const fromBase64Url = (part: string) => Buffer.from(part.replace(/-/g, "+").replace(/_/g, "/"), "base64");

/** The payload of a JWS Apple signed, or AppleSignatureError. */
export function verifyAppleJws<T = Record<string, unknown>>(jws: string, opts: VerifyOptions = {}): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppleSignatureError("not a signed transaction");
  let header: { alg?: string; x5c?: unknown };
  let payload: T & { environment?: string; data?: { environment?: string } };
  try {
    header = JSON.parse(fromBase64Url(parts[0]).toString("utf8"));
    payload = JSON.parse(fromBase64Url(parts[1]).toString("utf8"));
  } catch {
    throw new AppleSignatureError("unreadable");
  }
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new AppleSignatureError("not signed the way Apple signs");
  }
  let certs: X509Certificate[];
  try {
    certs = (header.x5c as string[]).map(c => new X509Certificate(Buffer.from(c, "base64")));
  } catch {
    throw new AppleSignatureError("unreadable certificate");
  }

  const environment = payload.environment ?? payload.data?.environment;
  if (environment === "Xcode" || environment === "LocalTesting") {
    if (!opts.allowXcode) throw new AppleSignatureError("StoreKit testing outside development");
  } else {
    if (certs.length !== 3) throw new AppleSignatureError("incomplete certificate chain");
    const [leaf, intermediate, root] = certs;
    if (root.fingerprint256 !== (opts.rootFingerprint ?? APPLE_ROOT_G3_SHA256)) {
      throw new AppleSignatureError("not Apple's root");
    }
    if (!intermediate.checkIssued(root) || !intermediate.verify(root.publicKey)
        || !leaf.checkIssued(intermediate) || !leaf.verify(intermediate.publicKey)) {
      throw new AppleSignatureError("broken certificate chain");
    }
    if (!leaf.raw.includes(LEAF_MARKER) || !intermediate.raw.includes(INTERMEDIATE_MARKER)) {
      throw new AppleSignatureError("not an App Store certificate");
    }
    const at = (opts.now ?? new Date()).getTime();
    for (const cert of certs) {
      if (Date.parse(cert.validFrom) > at || Date.parse(cert.validTo) < at) {
        throw new AppleSignatureError("certificate out of date");
      }
    }
  }
  const signed = verify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: certs[0].publicKey, dsaEncoding: "ieee-p1363" }, fromBase64Url(parts[2]));
  if (!signed) throw new AppleSignatureError("bad signature");
  return payload;
}

/** What one verified transaction grants: a plan until a moment, or nothing
 *  (another app's, an unknown product, refunded, or already over). */
export function planOf(tx: AppleTransaction, bundleId: string, now = Date.now()):
  { plan: "plus" | "max"; expiresAt: Date } | null {
  if (tx.bundleId !== bundleId) return null;
  const plan = APPLE_PRODUCTS[tx.productId];
  if (!plan || tx.revocationDate || typeof tx.expiresDate !== "number") return null;
  return tx.expiresDate > now ? { plan, expiresAt: new Date(tx.expiresDate) } : null;
}
