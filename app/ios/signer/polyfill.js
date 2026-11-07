// JavaScriptCore has no TextEncoder/TextDecoder or crypto: the parts viem uses.
if (typeof globalThis.TextEncoder === "undefined") {
  globalThis.TextEncoder = class { encode(s = "") { const u = unescape(encodeURIComponent(s)); const a = new Uint8Array(u.length); for (let i = 0; i < u.length; i++) a[i] = u.charCodeAt(i); return a; } };
}
if (typeof globalThis.TextDecoder === "undefined") {
  globalThis.TextDecoder = class { decode(b) { if (!b) return ""; const a = b instanceof Uint8Array ? b : new Uint8Array(b.buffer || b); let s = ""; for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]); try { return decodeURIComponent(escape(s)); } catch { return s; } } };
}
if (typeof globalThis.crypto === "undefined") globalThis.crypto = {};
if (!globalThis.crypto.getRandomValues) globalThis.crypto.getRandomValues = (a) => { const r = __native.random(a.length); for (let i = 0; i < a.length; i++) a[i] = r[i]; return a; };
if (typeof globalThis.queueMicrotask === "undefined") globalThis.queueMicrotask = (fn) => Promise.resolve().then(fn);
