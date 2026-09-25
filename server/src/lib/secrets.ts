/**
 * Things a model must never see: card numbers, CVVs, one-time codes,
 * passwords, government ids, API keys, wallet keys and recovery phrases.
 *
 * Before any prompt leaves for a model, each one is swapped for a placeholder
 * like [[S1]]; whatever the model writes back gets the real value put back in.
 * A message with a card number still gets rewritten, and the card number is
 * still in it, but no model ever read it.
 */

const PLACEHOLDER = /\[\[\s*S(\d+)\s*\]\]/g;

/** Luhn, the check digit every payment card carries. */
export function luhn(digits: string): boolean {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = digits.charCodeAt(digits.length - 1 - i) - 48;
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

const VERHOEFF_D = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7], [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3], [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];
const VERHOEFF_P = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7], [9, 4, 5, 3, 1, 2, 6, 8, 7, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/** Verhoeff, the check digit on an Aadhaar number. */
export function verhoeff(digits: string): boolean {
  let c = 0;
  for (let i = 0; i < digits.length; i++) {
    const d = digits.charCodeAt(digits.length - 1 - i) - 48;
    c = VERHOEFF_D[c][VERHOEFF_P[i % 8][d]];
  }
  return c === 0;
}

/** IBAN mod-97. */
function ibanValid(raw: string): boolean {
  const s = raw.replace(/\s/g, "").toUpperCase();
  const moved = s.slice(4) + s.slice(0, 4);
  let rem = 0;
  for (const ch of moved) {
    const v = /[A-Z]/.test(ch) ? String(ch.charCodeAt(0) - 55) : ch;
    for (const digit of v) rem = (rem * 10 + Number(digit)) % 97;
  }
  return rem === 1;
}

/** Each rule finds a span; `group` names the capture that is the secret
 *  itself (the keyword before it stays readable, so the rewrite still
 *  knows it is a password). */
interface Rule {
  re: RegExp;
  group?: number;
  valid?: (value: string) => boolean;
}

const RULES: Rule[] = [
  // Recovery phrases first: twelve or more words after the name for one.
  { re: /\b(?:seed|recovery|secret|mnemonic|backup)\s+(?:phrase|words)\b\s*(?:is|are|:|=|-)?\s*((?:[a-z]{3,8}[\s,]+){11,23}[a-z]{3,8})\b/gi, group: 1 },
  // Wallet private keys (base58, 64 to 88 characters) and hex keys.
  { re: /\b([1-9A-HJ-NP-Za-km-z]{64,88})\b/g, group: 1 },
  { re: /\b(?:0x)?([0-9a-fA-F]{64})\b/g, group: 1 },
  // API keys that name themselves.
  { re: /\b((?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,})\b/g, group: 1 },
  // Card numbers: 13 to 19 digits, grouped or not, with a valid check digit.
  { re: /(?<![\d-])((?:\d[ -]?){12,18}\d)(?![\d-])/g, group: 1,
    valid: v => { const d = v.replace(/\D/g, ""); return d.length >= 13 && d.length <= 19 && luhn(d); } },
  // Aadhaar: 12 digits in threes of four, with its check digit.
  { re: /(?<!\d)([2-9]\d{3}[ -]?\d{4}[ -]?\d{4})(?!\d)/g, group: 1,
    valid: v => verhoeff(v.replace(/\D/g, "")) },
  // IBAN.
  { re: /\b([A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?)\b/g, group: 1, valid: ibanValid },
  // US SSN and Indian PAN.
  { re: /\b(\d{3}-\d{2}-\d{4})\b/g, group: 1 },
  { re: /\b([A-Z]{5}\d{4}[A-Z])\b/g, group: 1 },
  // Codes that say what they are.
  { re: /\b(?:cvv2?|cvc2?|cid|csc|security code)\b\s*(?:is|:|=|-|#)?\s*(\d{3,4})\b/gi, group: 1 },
  { re: /\b(?:otp|one[- ]time (?:password|passcode|code|pin)|verification code|passcode|pin(?: code| number)?|2fa code|auth(?:entication)? code|login code|security pin|upi pin|atm pin)\b\s*(?:is|:|=|-|#)?\s*(\d{4,8})\b/gi, group: 1 },
  { re: /\b(?:password|passwd|pwd|wi-?fi password|wifi pass)\b\s*(?:is|:|=|-)?\s*([^\s,;]{3,64})/gi, group: 1,
    valid: v => !/^(is|was|the|my|your|for|and|to|changed|reset|expired|incorrect|wrong)$/i.test(v) },
];

export class SecretVault {
  private values: string[] = [];

  get count(): number {
    return this.values.length;
  }

  /** The same value always gets the same placeholder. */
  private slot(value: string): string {
    let i = this.values.indexOf(value);
    if (i < 0) {
      this.values.push(value);
      i = this.values.length - 1;
    }
    return `[[S${i + 1}]]`;
  }

  mask(text: string): string {
    let out = text;
    for (const rule of RULES) {
      out = out.replace(rule.re, (whole: string, ...groups: unknown[]) => {
        const g = rule.group ?? 0;
        const value = g === 0 ? whole : String(groups[g - 1] ?? "");
        if (!value || /\[\[S\d+\]\]/.test(value)) return whole;
        if (rule.valid && !rule.valid(value)) return whole;
        const at = whole.lastIndexOf(value);
        return whole.slice(0, at) + this.slot(value) + whole.slice(at + value.length);
      });
    }
    return out;
  }

  restore(text: string): string {
    if (this.values.length === 0) return text;
    const json = /^\s*[{[]|```json/.test(text);
    return text.replace(PLACEHOLDER, (whole, n: string) => {
      const value = this.values[Number(n) - 1];
      if (value === undefined) return whole;
      // Inside a JSON reply a quote or backslash in the value would break it.
      return json ? JSON.stringify(value).slice(1, -1) : value;
    });
  }

  /** Streams tokens back with values restored, holding a placeholder that
   *  is split across tokens until it is whole. */
  restoringStream(forward: (t: string) => void): { push: (t: string) => void; flush: () => void; reset: () => void } {
    let held = "";
    return {
      /** The model was dropped mid-answer: what it half-said is not kept. */
      reset: () => {
        held = "";
      },
      push: (t: string) => {
        held += t;
        const partial = held.match(/\[(?:\[\s*(?:S\d*\s*(?:\])?)?)?$/);
        const cut = partial ? partial.index! : held.length;
        const ready = held.slice(0, cut);
        held = held.slice(cut);
        if (ready) forward(this.values.length ? ready.replace(PLACEHOLDER, (w, n: string) =>
          this.values[Number(n) - 1] ?? w) : ready);
      },
      flush: () => {
        if (held) forward(held);
        held = "";
      },
    };
  }
}

/** The line added to a prompt that carries placeholders. */
export const KEEP_PLACEHOLDERS =
  "\n\nSome private details were replaced with placeholders like [[S1]]. Keep every placeholder exactly as written, in the same place.";
