"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useId, useImperativeHandle, useRef, useState, type CSSProperties, type ReactNode, type Ref } from "react";
import {
  CLIP_AGE, CLIPS, EMOJI, HOLD_MS, LANGS, POS, ROWS_123, ROWS_ABC, SEARCH_SUGGEST, SKILLS, SPACE_HOLD_MS, SHORTHAND, TONES, VAULT, WEATHER,
  autocorrect, calc, classify, contextual, isLink, proofread, rewrite, rowOf, searchCards, short, shortAddr, solAddress, suggest, translate,
  SWAP_RATE, type ActResult, type Card, type Lang, type Panel, type PayHint, type SearchTab,
} from "./data";
import { hub } from "./hub";
import { MagicBlockLogo, MagicBlockMark, SolIcon, UsdcIcon } from "./brands";
import * as I from "./icons";
import { ClockFace, GoogleG, SunArc, WeatherGlyph } from "./visuals";

export type SearchView = "suggest" | "type" | "results";

export type KbSnapshot = {
  text: string;
  panel: Panel;
  tab: SearchTab;
  query: string;
  searchView: SearchView;
  results: number;
  mode: "abc" | "123";
  act: ActResult["kind"] | "thinking" | null;
  mine: string | null;
  calc: string | null;
  translation: string | null;
  lang: Lang;
  auto: boolean;
  clip: string | null;
  addr: string | null;
  wallet: { tab: "send" | "swap"; stage: "form" | "sending" | "done" } | null;
};

export type Coach = { target: string; label: string } | null;

/** Lets the page drive the keyboard like a visitor would (the scroll autopilot). */
export type KeyboardApi = {
  target: () => HTMLElement | null;
  run: (target: string, hold: boolean) => Promise<void>;
};

type State = {
  text: string;
  mode: "abc" | "123";
  shift: boolean;
  panel: Panel;
  tab: SearchTab;
  query: string;
  searchView: SearchView;
  results: Card[] | null;
  searching: boolean;
  act: ActResult | null;
  lang: Lang;
  down: string[];
  holding: { key: string; ms: number } | null;
  fired: string | null;
  ripple: { id: number; origin: string } | null;
  ai: boolean;
  fix: { from: string; to: string; at: number } | null;
  flash: { at: number; len: number; id: number } | null;
  toast: string | null;
  auto: boolean;
  clip: { text: string; used: boolean } | null;
  wal: Wal;
};

type Wal = {
  tab: "send" | "swap";
  to: string;
  name?: string;
  amount: string;
  token: "USDC" | "SOL";
  private: boolean;
  stage: "form" | "sending" | "done";
  step: number;
  usdc: number;
  sol: number;
  flipped: boolean;
  swap: "form" | "swapping" | "done";
};

const WAL: Wal = {
  tab: "send", to: "", amount: "200", token: "USDC", private: true, stage: "form", step: 0,
  usdc: 1240.18, sol: 8.42, flipped: false, swap: "form",
};

const SELL = 1.5;
const money = (n: number) => n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const INITIAL: State = {
  text: "", mode: "abc", shift: false, panel: null, tab: "google", query: "", searchView: "suggest", results: null, searching: false,
  act: null, lang: "hi", down: [], holding: null, fired: null, ripple: null, ai: false, fix: null, flash: null, toast: null, auto: false,
  clip: null, wal: WAL,
};

const TOOLS = [
  { id: "search", label: "Search", Icon: I.SearchIcon },
  { id: "clip", label: "Clipboard", Icon: I.ClipIcon },
  { id: "vault", label: "Vault", Icon: I.IdCardIcon },
  { id: "wallet", label: "Wallet", Icon: I.WalletIcon },
  { id: "emoji", label: "Emoji", Icon: I.EmojiIcon },
  { id: "translate", label: "Translate", Icon: I.TranslateIcon },
];

const MENU = [
  { id: "search", label: "Search", Icon: I.SearchIcon },
  { id: "tones", label: "Rewrite", Icon: I.WandIcon },
  { id: "translate", label: "Translate", Icon: I.TranslateIcon },
  { id: "vault", label: "Vault", Icon: I.IdCardIcon },
  { id: "wallet", label: "Wallet", Icon: I.WalletIcon },
  { id: "clip", label: "Clipboard", Icon: I.ClipIcon },
  { id: "emoji", label: "Emoji", Icon: I.EmojiIcon },
  { id: "act", label: "Ask Glyf", Icon: I.SparkIcon },
];

const TABS: { id: SearchTab; label: string; Icon: (p: { className?: string }) => ReactNode }[] = [
  { id: "google", label: "Google", Icon: I.SearchIcon },
  { id: "youtube", label: "YouTube", Icon: I.PlayRectIcon },
  { id: "maps", label: "Maps", Icon: I.PinIcon },
];

const TITLES: Partial<Record<Exclude<Panel, null>, [string, (p: { className?: string }) => ReactNode]>> = {
  menu: ["Glyf", I.GridIcon],
  vault: ["Vault", I.IdCardIcon],
  clip: ["Clipboard", I.ClipIcon],
  emoji: ["Emoji", I.EmojiIcon],
  tones: ["Rewrite", I.WandIcon],
  act: ["Glyf", I.SparkIcon],
  skills: ["Skills", I.BoltIcon],
  chips: ["Ask Glyf", I.SparkIcon],
  wallet: ["Wallet", I.WalletIcon],
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
const lastWord = (t: string) => t.match(/[A-Za-z']+$/)?.[0] ?? "";
const ease = [0.22, 1, 0.36, 1] as const;

const MiniMap = ({ seed = 0 }: { seed?: number }) => (
  <svg className="kb-map" viewBox="0 0 160 90" preserveAspectRatio="xMidYMid slice" aria-hidden>
    <rect width="160" height="90" className="kb-map-bg" />
    <g transform={`rotate(${(seed % 40) - 20} 80 45)`}>
      <path d="M-20 62C30 50 70 72 180 38" className="kb-road" />
      <path d="M46-20 72 110" className="kb-road" />
      <path d="M118-20c-12 40 20 70 6 130" className="kb-road kb-road--thin" />
      <path d="M-20 20 180 28" className="kb-road kb-road--thin" />
    </g>
    <circle cx="80" cy="40" r="15" className="kb-map-halo" />
    <path d="M80 50s8.5-7 8.5-13.2a8.5 8.5 0 1 0-17 0C71.5 43 80 50 80 50z" className="kb-pin" />
    <circle cx="80" cy="36.6" r="2.8" className="kb-pin-dot" />
  </svg>
);

export { MiniMap };

type Props = {
  seed: { key: string; text?: string; lang?: Lang; pay?: PayHint };
  /** Something the visitor copied elsewhere on the page (a chat bubble). */
  copied?: { key: string; text: string } | null;
  draftId: string;
  coach?: Coach;
  /** Text the keyboard types for the visitor, key by key, when `key` changes. */
  autotype?: { key: string; text: string } | null;
  onSend?: (text: string, layoutId: string) => void;
  onSnapshot?: (snap: KbSnapshot) => void;
  apiRef?: Ref<KeyboardApi>;
};

export default function Keyboard({ seed, draftId, coach = null, autotype = null, copied = null, onSend, onSnapshot, apiRef }: Props) {
  const id = useId();
  const root = useRef<HTMLDivElement>(null);
  const [s, setS] = useState<State>(INITIAL);
  const st = useRef(s);
  const set = (p: Partial<State> | ((x: State) => Partial<State>)) => {
    const next = { ...st.current, ...(typeof p === "function" ? p(st.current) : p) };
    st.current = next;
    setS(next);
  };

  const learned = useRef(new Set<string>());
  const engagedAt = useRef(0);
  const streamTok = useRef(0);
  const searchTok = useRef(0);
  const actTok = useRef(0);
  const autoTok = useRef(0);
  const seedKey = useRef(seed.key);
  seedKey.current = seed.key;
  const ptr = useRef<{ key: string; fired: boolean; timer: number; repeat: number } | null>(null);
  const phys = useRef(new Map<string, { timer: number; fired: boolean }>());
  const cbs = useRef({ onSend, onSnapshot, draftId });
  cbs.current = { onSend, onSnapshot, draftId };

  /* ── text ─────────────────────────────────────────────── */

  const toast = (msg: string) => {
    set({ toast: msg });
    window.setTimeout(() => set((x) => (x.toast === msg ? { toast: null } : {})), 2200);
  };

  const pressVisual = (k: string) => {
    set((x) => ({ down: [...x.down, k] }));
    window.setTimeout(() => set((x) => ({ down: x.down.filter((d) => d !== k) })), 130);
  };

  /** AI output streams in with the glow on. */
  const stream = (to: string) => {
    const tok = ++streamTok.current;
    const from = [...st.current.text];
    const target = [...to];
    let i = 0;
    while (i < from.length && i < target.length && from[i] === target[i]) i++;
    set({ text: target.slice(0, i).join(""), fix: null, flash: null, ai: true });
    const step = target.length - i > 70 ? 2 : 1;
    const tick = () => {
      if (tok !== streamTok.current) return set({ ai: false });
      i = Math.min(target.length, i + step);
      set({ text: target.slice(0, i).join("") });
      if (i >= target.length) window.setTimeout(() => tok === streamTok.current && set({ ai: false }), 450);
      else window.setTimeout(tick, 22);
    };
    window.setTimeout(tick, 240);
  };

  const typeChar = (ch: string) => {
    streamTok.current++;
    const x = st.current;
    if (x.panel === "search") return set({ query: x.query + ch, results: null, searchView: "type" });
    const c = x.shift && x.mode === "abc" ? ch.toUpperCase() : ch;
    const keep = x.panel === "translate";
    set({ text: x.text + c, shift: false, fix: null, ai: false, ...(keep ? {} : { panel: null, act: null }) });
  };

  const space = () => {
    streamTok.current++;
    const x = st.current;
    if (x.panel === "search") return set({ query: x.query + " ", results: null, searchView: "type" });
    const close = x.panel === "translate" ? {} : { panel: null, act: null };
    const sh = x.text.match(/;([a-z]+)$/i);
    const exp = sh && SHORTHAND[sh[1].toLowerCase()];
    if (sh && exp) {
      const at = x.text.length - sh[0].length;
      return set({ text: x.text.slice(0, at) + exp + " ", fix: null, flash: { at, len: exp.length, id: Date.now() }, ...close });
    }
    const w = lastWord(x.text);
    const fix = w ? autocorrect(w, learned.current) : null;
    if (fix) {
      const at = x.text.length - w.length;
      set({ text: x.text.slice(0, at) + fix + " ", fix: { from: w, to: fix, at }, flash: { at, len: fix.length, id: Date.now() }, ...close });
    } else set({ text: x.text + " ", fix: null, ...close });
  };

  const backspace = () => {
    streamTok.current++;
    const x = st.current;
    if (x.panel === "search") return set({ query: [...x.query].slice(0, -1).join(""), results: null, searchView: "type" });
    set({ text: [...x.text].slice(0, -1).join(""), fix: null, flash: null });
  };

  const send = () => {
    const x = st.current;
    const msg = x.text.trim();
    if (!msg) return;
    streamTok.current++;
    cbs.current.onSend?.(msg, cbs.current.draftId);
    set({ text: "", fix: null, flash: null, ai: false, panel: x.panel === "translate" ? "translate" : null, act: null, shift: false });
  };

  const enter = () => {
    const x = st.current;
    if (x.panel === "search") return void runSearch();
    send();
  };

  /** Drops a value into the message with a highlight sweep over it. */
  const drop = (val: string, replace = false) => {
    streamTok.current++;
    const base = replace ? "" : st.current.text;
    const sep = base && !/\s$/.test(base) ? " " : "";
    const at = base.length + sep.length;
    set({ text: base + sep + val, panel: null, act: null, results: null, fix: null, flash: { at, len: val.length, id: Date.now() } });
  };

  /* ── actions ──────────────────────────────────────────── */

  const openSearch = () => set({ panel: "search", results: null, query: "", searching: false, searchView: "suggest" });

  const runSearch = async () => {
    const q = st.current.query.trim();
    if (!q) return;
    const tok = ++searchTok.current;
    set({ searching: true, results: [], searchView: "results" });
    await sleep(700);
    if (tok !== searchTok.current || st.current.panel !== "search") return;
    set({ searching: false, results: searchCards(st.current.tab, st.current.query) });
  };

  const act = async () => {
    const src = st.current.text.trim();
    if (!src) return set({ panel: "chips" });
    const tok = ++actTok.current;
    set({ panel: "act", act: null, ai: true });
    await sleep(1100);
    if (tok !== actTok.current || st.current.panel !== "act") return;
    set({ act: classify(src), ai: false });
  };

  /** The app's ignition: origin key goes solid accent, a tint wave rolls out. */
  const ignite = (key: string) => {
    const rid = Date.now();
    set({ fired: key, holding: null, ripple: { id: rid, origin: `${rowOf(key)}-${key}` } });
    window.setTimeout(() => set((x) => (x.ripple?.id === rid ? { ripple: null, fired: null } : {})), 900);
  };

  const fireHold = (key: string) => {
    ignite(key);
    const later = (fn: () => void) => window.setTimeout(fn, 170);
    switch (key) {
      case "space":
        return later(() => void act());
      case "p":
        if (!st.current.text.trim()) return toast("Nothing to proofread yet");
        return stream(proofread(st.current.text));
      case "t":
        return later(() => set({ panel: st.current.panel === "translate" ? null : "translate" }));
      case "r":
        return later(() => set({ panel: "tones" }));
      case "s":
        return later(() => set({ panel: "vault" }));
      case "w": {
        const t = st.current.text;
        return stream(`${t}${t && !/\s$/.test(t) ? " " : ""}${WEATHER}`);
      }
    }
  };

  /** Private send through MagicBlock's Private Ephemeral Rollup (TEE on Intel TDX). */
  const runPayment = async () => {
    const x = st.current;
    if (x.wal.stage === "sending") return;
    const amt = parseFloat(x.wal.amount) || 0;
    set({ wal: { ...x.wal, stage: "sending", step: 0 }, ai: x.wal.private });
    for (let i = 1; i <= 3; i++) {
      await sleep(780);
      if (st.current.panel !== "wallet") return set({ ai: false, wal: { ...st.current.wal, stage: "form", step: 0 } });
      set((y) => ({ wal: { ...y.wal, step: i } }));
    }
    await sleep(650);
    const y = st.current;
    const receipt = `💸 $${amt} ${y.wal.token} · ${y.wal.private ? "sent privately" : "sent"}`;
    streamTok.current++;
    set({
      panel: null,
      ai: false,
      text: receipt,
      fix: null,
      flash: { at: 0, len: receipt.length, id: Date.now() },
      clip: y.clip ? { ...y.clip, used: true } : null,
      wal: { ...y.wal, stage: "done", step: 0, usdc: y.wal.token === "USDC" ? y.wal.usdc - amt : y.wal.usdc },
    });
  };

  /** Swap quote and fill, routed by Jupiter (illustrative numbers). */
  const runSwap = async () => {
    const x = st.current;
    if (x.wal.swap !== "form") return;
    set({ wal: { ...x.wal, swap: "swapping" } });
    await sleep(1100);
    const y = st.current;
    const usdcOut = SELL * SWAP_RATE;
    const wal = y.wal.flipped
      ? { ...y.wal, usdc: y.wal.usdc - usdcOut, sol: y.wal.sol + SELL }
      : { ...y.wal, usdc: y.wal.usdc + usdcOut, sol: y.wal.sol - SELL };
    set({ wal: { ...wal, swap: "done" } });
    await sleep(1500);
    set((z) => ({ wal: { ...z.wal, swap: "form" } }));
  };

  const perform = (pid: string) => {
    const i = pid.indexOf(":");
    const kind = i < 0 ? pid : pid.slice(0, i);
    const arg = i < 0 ? "" : pid.slice(i + 1);
    const x = st.current;
    engagedAt.current = Date.now();
    hub.touch(id);
    switch (kind) {
      case "g":
        return set({ panel: x.panel === "menu" ? null : "menu" });
      case "close":
        searchTok.current++;
        actTok.current++;
        return set({ panel: null, act: null, results: null, searching: false, ai: false });
      case "tool":
      case "menu":
        if (arg === "search") return openSearch();
        if (arg === "wallet") return set({ panel: "wallet", act: null, wal: { ...x.wal, to: solAddress(x.text) ?? x.wal.to, stage: "form", step: 0 } });
        if (arg === "act") return void act();
        return set({ panel: arg as Panel, act: null });
      case "tab":
        set({ tab: arg as SearchTab });
        return void (x.query.trim() ? runSearch() : set({ results: null, searchView: "suggest" }));
      case "query":
        return set({ searchView: x.searchView === "type" && !x.query ? "suggest" : "type", results: null });
      case "sugg":
        set({ query: SEARCH_SUGGEST[x.tab][Number(arg)] });
        return void runSearch();
      case "card": {
        const c = x.results?.[Number(arg)];
        return c ? drop(c.insert) : undefined;
      }
      case "act": {
        const a = x.act;
        if (!a || arg === "ok" || a.kind === "refuse") return set({ panel: null, act: null });
        if (a.kind === "cards") return drop(a.cards[Number(arg)]?.insert ?? a.cards[0].insert, true);
        if (a.kind === "list") return drop(`${a.title}\n${a.items.map((t) => `• ${t}`).join("\n")}`, true);
        set({ panel: null, act: null });
        return stream(a.options[Number(arg)]?.text ?? a.options[0].text);
      }
      case "tone":
        if (!x.text.trim()) return;
        set({ panel: null });
        return stream(rewrite(x.text, arg));
      case "vault": {
        const v = VAULT.find((item) => item.id === arg);
        return v ? drop(v.value) : undefined;
      }
      case "clip": {
        const c = CLIPS[Number(arg)];
        if (isLink(c)) return void window.open(c, "_blank", "noopener,noreferrer");
        return drop(c);
      }
      case "emoji":
        return set({ text: x.text + EMOJI[Number(arg)] });
      case "skill":
        set({ panel: null });
        return fireHold(arg);
      case "lang":
        return set({ lang: arg as Lang });
      case "translate": {
        const out = translate(x.text, x.lang);
        if (!out || out.endsWith("…")) return;
        set({ panel: null });
        return stream(out);
      }
      case "chip":
        return set({ panel: null });
      case "wtab":
        return set({ wal: { ...x.wal, tab: arg as Wal["tab"] } });
      case "wallet":
        if (arg === "private") return set({ wal: { ...x.wal, private: !x.wal.private } });
        if (arg === "send") return void runPayment();
        return;
      case "swap":
        if (arg === "flip") return set({ wal: { ...x.wal, flipped: !x.wal.flipped } });
        if (arg === "go") return void runSwap();
        return;
      case "strip": {
        if (arg === "paste") {
          if (!x.clip) return;
          set({ clip: { ...x.clip, used: true } });
          return drop(x.clip.text);
        }
        if (arg === "pay") {
          const to = solAddress(x.text);
          if (!to) return;
          return set({ panel: "wallet", wal: { ...x.wal, tab: "send", to, stage: "form", step: 0 } });
        }
        if (arg === "vault") {
          const v = contextual(x.text);
          return v ? drop(v.value) : undefined;
        }
        if (arg === "calc") {
          const c = calc(x.text);
          if (!c) return;
          const base = c.eq ? x.text.replace(/\s*$/, " ") : `${x.text.replace(/\s*$/, "")} = `;
          return set({ text: `${base}${c.value}`, flash: { at: base.length, len: c.value.length, id: Date.now() }, fix: null });
        }
        const w = lastWord(x.text);
        const pick = arg === "lit" ? w : suggest(w, learned.current)[Number(arg)];
        if (!pick) return;
        if (arg === "lit") learned.current.add(w.toLowerCase());
        const at = x.text.length - w.length;
        return set({ text: x.text.slice(0, at) + pick + " ", fix: null, flash: { at, len: pick.length, id: Date.now() } });
      }
      case "undo": {
        const f = x.fix;
        if (!f || !x.text.startsWith(f.to, f.at)) return;
        learned.current.add(f.from.toLowerCase());
        set({ text: x.text.slice(0, f.at) + f.from + x.text.slice(f.at + f.to.length), fix: null, flash: null });
        return toast(`Learned “${f.from}”`);
      }
      case "send":
        return send();
    }
  };

  /* ── input: pointer, physical keys ────────────────────── */

  const engage = () => {
    hub.touch(id);
    engagedAt.current = Date.now();
  };

  const holdable = (k: string) => (k === "space" || (!!SKILLS[k] && st.current.mode === "abc")) && st.current.panel !== "search";
  const holdMs = (k: string) => (k === "space" ? SPACE_HOLD_MS : HOLD_MS);

  const tap = (k: string) => {
    switch (k) {
      case "space": return space();
      case "shift": return set((x) => ({ shift: x.mode === "abc" && !x.shift }));
      case "mode": return set((x) => ({ mode: x.mode === "abc" ? "123" : "abc", shift: false }));
      case "emoji": return set((x) => ({ panel: x.panel === "emoji" ? null : "emoji" }));
      case "return": return enter();
      case "backspace": return;
      default: return typeChar(k);
    }
  };

  /** A real keypress takes over from the keyboard's own typing. */
  const interrupt = () => {
    if (!st.current.auto) return;
    autoTok.current++;
    set({ auto: false });
  };

  const pointerDown = (k: string) => {
    engage();
    interrupt();
    set((x) => ({ down: [...x.down.filter((d) => d !== k), k] }));
    const p = { key: k, fired: false, timer: 0, repeat: 0 };
    if (k === "backspace") {
      backspace();
      p.timer = window.setTimeout(() => (p.repeat = window.setInterval(backspace, 70)), 420);
    } else if (holdable(k)) {
      set({ holding: { key: k, ms: holdMs(k) } });
      const started = seedKey.current;
      p.timer = window.setTimeout(() => {
        if (started !== seedKey.current || ptr.current !== p) return;
        p.fired = true;
        fireHold(k);
      }, holdMs(k));
    }
    ptr.current = p;
  };

  const pointerUp = (k: string, cancel = false) => {
    const p = ptr.current;
    set((x) => ({ down: x.down.filter((d) => d !== k), holding: x.holding?.key === k ? null : x.holding }));
    if (!p || p.key !== k) return;
    clearTimeout(p.timer);
    clearInterval(p.repeat);
    ptr.current = null;
    if (!p.fired && !cancel) tap(k);
  };

  const physicalDown = (k: string, ch: string) => {
    interrupt();
    for (const [other, h] of phys.current) if (other !== k) clearTimeout(h.timer);
    const before = st.current.text;
    set((x) => ({ down: [...x.down.filter((d) => d !== k), k] }));
    const canHold = holdable(k);
    if (k === "space") space();
    else typeChar(ch);
    if (!canHold) return;
    set({ holding: { key: k, ms: holdMs(k) } });
    const h = { timer: 0, fired: false };
    const started = seedKey.current;
    h.timer = window.setTimeout(() => {
      if (started !== seedKey.current) return;
      h.fired = true;
      set({ text: before, fix: null, flash: null });
      fireHold(k);
    }, holdMs(k));
    phys.current.set(k, h);
  };

  const physicalUp = (k: string) => {
    const h = phys.current.get(k);
    if (h) clearTimeout(h.timer);
    phys.current.delete(k);
    set((x) => ({ down: x.down.filter((d) => d !== k), holding: x.holding?.key === k ? null : x.holding }));
  };

  const onKey = (e: KeyboardEvent, down: boolean) => {
    const k = e.key;
    const letter = /^[a-z]$/i.test(k);
    if (!down) {
      if (letter) physicalUp(k.toLowerCase());
      else if (k === " ") physicalUp("space");
      return true;
    }
    if (letter) {
      engage();
      if (!e.repeat) physicalDown(k.toLowerCase(), k);
      return true;
    }
    if (Date.now() - engagedAt.current > 30000) return false;
    if (k === " ") {
      engage();
      if (!e.repeat) physicalDown("space", " ");
      return true;
    }
    if (k === "Backspace") return engage(), pressVisual("backspace"), backspace(), true;
    if (k === "Enter") return engage(), pressVisual("return"), enter(), true;
    if (k === "Escape") return perform("close"), true;
    if (k.length === 1 && /[0-9.,?!'";:@&()\-+*/=%₹×]/.test(k)) {
      engage();
      pressVisual(k === "*" ? "×" : k);
      typeChar(k === "*" ? "×" : k);
      return true;
    }
    return false;
  };

  const keyRef = useRef(onKey);
  keyRef.current = onKey;

  useImperativeHandle(apiRef, () => ({
    target: () => root.current?.querySelector<HTMLElement>(".is-coach") ?? null,
    run: async (target, hold) => {
      if (target.startsWith("key:")) {
        const k = target.slice(4);
        pointerDown(k);
        await sleep(hold ? holdMs(k) + 90 : 110);
        pointerUp(k);
        return;
      }
      perform(target);
    },
  }));

  useEffect(() => hub.register(id, { el: () => root.current, key: (e, d) => keyRef.current(e, d) }), [id]);


  useEffect(() => {
    streamTok.current++;
    searchTok.current++;
    actTok.current++;
    autoTok.current++;
    if (ptr.current) {
      clearTimeout(ptr.current.timer);
      clearInterval(ptr.current.repeat);
      ptr.current = null;
    }
    for (const h of phys.current.values()) clearTimeout(h.timer);
    phys.current.clear();
    const keep = st.current;
    set({
      ...INITIAL,
      text: seed.text ?? "",
      lang: seed.lang ?? "hi",
      clip: keep.clip,
      wal: { ...WAL, usdc: keep.wal.usdc, sol: keep.wal.sol, amount: seed.pay?.amount ?? WAL.amount, token: seed.pay?.token ?? WAL.token, name: seed.pay?.name },
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seed.key]);

  useEffect(() => {
    if (!autotype) return;
    const tok = ++autoTok.current;
    const alive = () => tok === autoTok.current;
    void (async () => {
      set({ auto: true });
      await sleep(450);
      for (const ch of autotype.text) {
        if (!alive()) return;
        const lower = ch.toLowerCase();
        const want = ch === " " ? null : ROWS_ABC.some((r) => r.includes(lower)) ? "abc" : ROWS_123.some((r) => r.includes(ch)) ? "123" : null;
        if (want && want !== st.current.mode) {
          pressVisual("mode");
          set({ mode: want, shift: false });
          await sleep(220);
          if (!alive()) return;
        }
        pressVisual(ch === " " ? "space" : want === "abc" ? lower : ch);
        if (ch === " ") space();
        else typeChar(ch);
        await sleep(ch === " " ? 130 : 90 + Math.random() * 70);
      }
      if (alive()) set({ auto: false });
    })();
    return () => {
      autoTok.current++;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autotype?.key]);

  useEffect(() => {
    if (copied) set({ clip: { text: copied.text, used: false } });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [copied?.key]);

  useEffect(() => {
    const noPanel = !s.panel;
    cbs.current.onSnapshot?.({
      text: s.text,
      panel: s.panel,
      tab: s.tab,
      query: s.query,
      searchView: s.searchView,
      results: s.results?.length ?? 0,
      mode: s.mode,
      act: s.panel === "act" ? (s.act ? s.act.kind : "thinking") : null,
      mine: noPanel ? contextual(s.text)?.id ?? null : null,
      calc: noPanel ? calc(s.text)?.value ?? null : null,
      translation: s.panel === "translate" ? translate(s.text, s.lang) : null,
      lang: s.lang,
      auto: s.auto,
      clip: s.clip && !s.clip.used ? s.clip.text : null,
      addr: solAddress(s.text),
      wallet: s.panel === "wallet" ? { tab: s.wal.tab, stage: s.wal.stage } : null,
    });
  }, [s]);

  /* ── render ───────────────────────────────────────────── */

  const isCoach = (pid: string) => coach?.target === pid;
  const co = (pid: string) => (isCoach(pid) ? "is-coach" : "");
  const tip = (pid: string) =>
    isCoach(pid) ? (
      <motion.span key={`tip-${coach!.label}`} className="kb-coach" initial={{ opacity: 0, y: 6, scale: 0.9 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 26 }}>
        {coach!.label}
      </motion.span>
    ) : null;

  const covering = !!s.panel && s.panel !== "translate" && s.panel !== "chips" && !(s.panel === "search" && s.searchView === "type");
  const pos = POS[s.mode];
  const origin = s.ripple ? pos[s.ripple.origin] : null;

  const renderKey = (k: string, row: number, o: { span?: number; start?: number; fn?: boolean; label?: ReactNode; aria?: string; cls?: string } = {}) => {
    const rid = `${row}-${k}`;
    const isDown = s.down.includes(k);
    const holding = s.holding?.key === k;
    const glyph = s.shift && s.mode === "abc" ? k.toUpperCase() : k;
    const p = pos[rid];
    const delay = origin && p ? Math.hypot(p[0] - origin[0], (p[1] - origin[1]) * 1.2) * 26 : 0;
    const cid = `key:${k}`;
    return (
      <button
        key={rid}
        type="button"
        tabIndex={-1}
        className={cx("kb-key", o.fn && "fn", o.cls, isDown && "is-down", holding && "is-holding", s.fired === k && "is-ignite", co(cid))}
        style={{ gridColumn: `${o.start ? `${o.start} / ` : ""}span ${o.span ?? 2}` }}
        data-k={k}
        aria-label={o.aria ?? k}
        onPointerDown={(e) => {
          e.preventDefault();
          e.currentTarget.setPointerCapture?.(e.pointerId);
          pointerDown(k);
        }}
        onPointerUp={() => pointerUp(k)}
        onPointerCancel={() => pointerUp(k, true)}
        onContextMenu={(e) => e.preventDefault()}
      >
        <span className="kb-face">{o.label ?? glyph}</span>
        {SKILLS[k] && s.mode === "abc" && <span className="kb-dot" />}
        {holding && <span className="kb-ring" style={{ animationDuration: `${s.holding?.ms}ms` } as CSSProperties} />}
        {s.ripple && s.ripple.origin !== rid && <span key={s.ripple.id} className="kb-tint" style={{ animationDelay: `${delay}ms` }} />}
        {isDown && !o.label && k.length === 1 && <span className="kb-balloon">{glyph}</span>}
        {tip(cid)}
      </button>
    );
  };

  const renderCard = (c: Card, pid: string, i: number) => (
    <motion.button
      key={pid}
      type="button"
      className={cx("kb-card", `kb-card--${c.kind}`, co(pid))}
      onClick={() => perform(pid)}
      initial={{ opacity: 0, y: 18, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ duration: 0.5, delay: i * 0.08, ease }}
    >
      {c.kind === "answer" ? (
        <span className={cx("kb-ans", c.visual && `kb-ans--${c.visual}`)}>
          <span className="kb-ans-top">
            <span className="kb-ans-g"><GoogleG /></span>
            <span className="kb-ans-meta">{c.meta}</span>
            <span className="kb-ans-when">Today</span>
          </span>
          <span className="kb-ans-main">
            <span className="kb-ans-copy">
              <span className="kb-ans-title">{c.title}</span>
              {c.sub && <span className="kb-ans-sub">{c.sub}</span>}
            </span>
            {(c.visual === "sunset" || c.visual === "sunrise") && <SunArc rise={c.visual === "sunrise"} />}
            {c.visual === "weather" && <WeatherGlyph />}
            {c.visual === "clock" && c.hm && <ClockFace h={c.hm[0]} m={c.hm[1]} />}
          </span>
          {c.facts && (
            <span className="kb-ans-facts">
              {c.facts.map(([k, v]) => (
                <span key={k} className="kb-ans-fact">
                  <i>{k}</i>
                  <b>{v}</b>
                </span>
              ))}
            </span>
          )}
        </span>
      ) : (
        <>
          {c.kind === "place" && <MiniMap seed={c.hue} />}
          {c.kind === "video" && (
            <span className="kb-thumb" style={{ "--h": c.hue } as CSSProperties}>
              <span className="kb-play"><I.PlayIcon /></span>
              <span className="kb-badge">{c.badge}</span>
            </span>
          )}
          {c.kind === "link" && <span className="kb-fav"><GoogleG /></span>}
          <span className="kb-card-body">
            <span className="kb-card-title">{c.title}</span>
            <span className="kb-card-meta">{c.meta}</span>
          </span>
        </>
      )}
      {tip(pid)}
    </motion.button>
  );

  const renderStrip = () => {
    if (s.panel === "search") {
      const tab = TABS.find((t) => t.id === s.tab)!;
      return (
        <div className="kb-search">
          <div className="kb-tabs" role="tablist" aria-label="Search in">
            {TABS.map((t) => (
              <button key={t.id} type="button" role="tab" aria-selected={s.tab === t.id} aria-label={t.label} className={cx("kb-tab", s.tab === t.id && "on", co(`tab:${t.id}`))} onClick={() => perform(`tab:${t.id}`)}>
                {s.tab === t.id && <motion.span layoutId={`${id}-tab`} className="kb-tab-bg" transition={{ type: "spring", bounce: 0.2, duration: 0.45 }} />}
                <t.Icon className="kb-tab-icon" />
                <span className="kb-tab-label">{t.label}</span>
                {tip(`tab:${t.id}`)}
              </button>
            ))}
          </div>
          <button type="button" className={cx("kb-query", co("query"))} onClick={() => perform("query")}>
            {s.query || <span className="ph">Search {tab.label}</span>}
            {s.searchView === "type" && <span className="kb-caret" />}
            {tip("query")}
          </button>
        </div>
      );
    }
    if (s.panel === "wallet") {
      return (
        <div className="kb-search">
          <div className="kb-tabs" role="tablist" aria-label="Wallet">
            {(["send", "swap"] as const).map((t) => (
              <button key={t} type="button" role="tab" aria-selected={s.wal.tab === t} className={cx("kb-tab", s.wal.tab === t && "on", co(`wtab:${t}`))} onClick={() => perform(`wtab:${t}`)}>
                {s.wal.tab === t && <motion.span layoutId={`${id}-wtab`} className="kb-tab-bg" transition={{ type: "spring", bounce: 0.2, duration: 0.45 }} />}
                {t === "send" ? <I.WalletIcon className="kb-tab-icon" /> : <I.SwapIcon className="kb-tab-icon" />}
                <span className="kb-lang-label">{t === "send" ? "Send" : "Swap"}</span>
                {tip(`wtab:${t}`)}
              </button>
            ))}
          </div>
          <span className="kb-wal-by">
            {s.wal.tab === "send" ? (
              <>
                <span className="kb-wal-lead">Private sends by</span> <MagicBlockLogo className="mb-logo" />
              </>
            ) : (
              "Routes by Jupiter"
            )}
          </span>
        </div>
      );
    }
    if (s.panel === "translate") {
      const out = translate(s.text, s.lang);
      return (
        <div className="kb-hud">
          <div className="kb-langs">
            {LANGS.map((l) => (
              <button key={l.id} type="button" className={cx("kb-lang", s.lang === l.id && "on", co(`lang:${l.id}`))} onClick={() => perform(`lang:${l.id}`)}>
                {s.lang === l.id && <motion.span layoutId={`${id}-lang`} className="kb-tab-bg" transition={{ type: "spring", bounce: 0.2, duration: 0.45 }} />}
                <span className="kb-lang-label long">{l.label}</span>
                <span className="kb-lang-label short">{l.id.toUpperCase()}</span>
                {tip(`lang:${l.id}`)}
              </button>
            ))}
          </div>
          <AnimatePresence mode="wait">
            <motion.div key={`${s.lang}-${out ?? ""}`} className="kb-hud-out" lang={s.lang} initial={{ opacity: 0, y: 6, filter: "blur(4px)" }} animate={{ opacity: 1, y: 0, filter: "blur(0px)" }} exit={{ opacity: 0, y: -6, filter: "blur(4px)" }} transition={{ duration: 0.22 }}>
              {out ?? "…"}
            </motion.div>
          </AnimatePresence>
          <button type="button" className={cx("kb-hud-go", co("translate:replace"))} disabled={!out || out.endsWith("…")} onClick={() => perform("translate:replace")}>
            Replace
            {tip("translate:replace")}
          </button>
        </div>
      );
    }
    if (s.panel) {
      const [title, Icon] = TITLES[s.panel] ?? ["", I.SparkIcon];
      return <div className="kb-title"><Icon /> {title}</div>;
    }
    const to = solAddress(s.text);
    if (to) {
      return (
        <motion.button key={`pay-${to}`} type="button" className={cx("kb-smart", co("strip:pay"))} onClick={() => perform("strip:pay")} initial={{ opacity: 0, y: 10, scale: 0.94 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 28 }}>
          <span className="kb-smart-k"><I.WalletIcon /> Pay</span>
          <span className="kb-smart-v">Send crypto to {shortAddr(to)}</span>
          {tip("strip:pay")}
        </motion.button>
      );
    }
    if (s.clip && !s.clip.used && !s.text.includes(s.clip.text)) {
      return (
        <motion.button key={`paste-${s.clip.text}`} type="button" className={cx("kb-smart", co("strip:paste"))} onClick={() => perform("strip:paste")} initial={{ opacity: 0, y: 10, scale: 0.94 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 28 }}>
          <span className="kb-smart-k"><I.PasteIcon /> Paste</span>
          <span className="kb-smart-v">{s.clip.text.length > 24 ? shortAddr(s.clip.text) : s.clip.text}</span>
          {tip("strip:paste")}
        </motion.button>
      );
    }
    const math = calc(s.text);
    if (math) {
      return (
        <motion.button key={`calc-${math.value}`} type="button" className={cx("kb-smart", co("strip:calc"))} onClick={() => perform("strip:calc")} initial={{ opacity: 0, y: 10, scale: 0.94 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 28 }}>
          <span className="kb-smart-k">=</span>
          <span className="kb-smart-v kb-num">{math.value}</span>
          {tip("strip:calc")}
        </motion.button>
      );
    }
    const mine = contextual(s.text);
    if (mine) {
      return (
        <motion.button key={`you-${mine.id}`} type="button" className={cx("kb-smart", co("strip:vault"))} onClick={() => perform("strip:vault")} initial={{ opacity: 0, y: 10, scale: 0.94 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ type: "spring", stiffness: 420, damping: 28 }}>
          <span className="kb-smart-k"><I.IdCardIcon /> {mine.label}</span>
          <span className="kb-smart-v">{short(mine)}</span>
          {tip("strip:vault")}
        </motion.button>
      );
    }
    const w = s.text.startsWith("💸") ? "" : lastWord(s.text);
    if (w) {
      const sug = suggest(w, learned.current);
      return (
        <div className="kb-sugg">
          <button type="button" className={co("strip:lit")} onClick={() => perform("strip:lit")}>“{w}”{tip("strip:lit")}</button>
          <button type="button" className={cx("best", co("strip:0"))} onClick={() => perform("strip:0")} disabled={!sug[0]}>
            {sug[0] ?? ""}
            {tip("strip:0")}
          </button>
          <button type="button" className={co("strip:1")} onClick={() => perform("strip:1")} disabled={!sug[1]}>
            {sug[1] ?? ""}
            {tip("strip:1")}
          </button>
        </div>
      );
    }
    if (s.toast) return <div className="kb-toast"><I.CheckIcon /> {s.toast}</div>;
    if (s.fix) {
      return (
        <motion.div className="kb-fix" key={`fix-${s.fix.at}`} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, ease }}>
          <span>
            <s>{s.fix.from}</s> <b>{s.fix.to}</b>
          </span>
          <button type="button" onClick={() => perform("undo")}><I.UndoIcon /> Undo</button>
        </motion.div>
      );
    }
    return (
      <div className="kb-tools">
        {TOOLS.map((t) => (
          <button key={t.id} type="button" aria-label={t.label} title={t.label} className={cx("kb-tool", co(`tool:${t.id}`))} onClick={() => perform(`tool:${t.id}`)}>
            <t.Icon />
            {tip(`tool:${t.id}`)}
          </button>
        ))}
      </div>
    );
  };

  const renderAct = () => {
    const a = s.act;
    if (!a) {
      return (
        <div className="kb-thinking">
          <span className="kb-orb" />
          <span className="kb-thinking-bars">
            <i />
            <i />
            <i />
          </span>
        </div>
      );
    }
    if (a.kind === "refuse") {
      return (
        <div className="kb-refuse">
          <I.LockIcon className="kb-refuse-icon" />
          <p><b>Card number spotted.</b> It stays on this phone.</p>
          <button type="button" className="kb-pill" onClick={() => perform("act:ok")}>OK</button>
        </div>
      );
    }
    if (a.kind === "cards") return <div className="kb-cards">{a.cards.map((c, i) => renderCard(c, `act:${i}`, i))}</div>;
    if (a.kind === "list") {
      return (
        <div className="kb-listcard">
          <div className="kb-listcard-head"><I.ListIcon /> {a.title}</div>
          <ul>{a.items.map((t, i) => <motion.li key={t} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.1 + i * 0.08 }}><span className="box" />{t}</motion.li>)}</ul>
          <button type="button" className={cx("kb-pill", co("act:0"))} onClick={() => perform("act:0")}>Send{tip("act:0")}</button>
        </div>
      );
    }
    return (
      <div className="kb-rows">
        {a.options.map((o, i) => (
          <motion.button key={o.id} type="button" className={cx("kb-row", co(`act:${i}`))} onClick={() => perform(`act:${i}`)} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: i * 0.07, ease }}>
            <span className="kb-row-k">{o.label}</span>
            <span className="kb-row-v">{o.text}</span>
            {tip(`act:${i}`)}
          </motion.button>
        ))}
      </div>
    );
  };

  const renderWallet = () => {
    const w = s.wal;
    const total = w.usdc + w.sol * SWAP_RATE;
    const steps = w.private
      ? [["Enclave verified", "Intel TDX"], ["In a Private Ephemeral Rollup", "magicblock"], ["Sent privately", "settled on Solana"]]
      : [["Signed", "your wallet"], ["Sent", "Solana"], ["Confirmed", "1 block"]];
    const sellTok = w.flipped ? "USDC" : "SOL";
    const buyTok = w.flipped ? "SOL" : "USDC";
    const sellAmt = w.flipped ? money(SELL * SWAP_RATE) : String(SELL);
    const buyAmt = w.flipped ? String(SELL) : money(SELL * SWAP_RATE);
    return (
      <div className="wal">
        <div className="wal-bal">
          <span className="wal-bal-k">Balance</span>
          <motion.b key={money(total)} className="wal-bal-v kb-num" initial={{ opacity: 0.4, y: 4 }} animate={{ opacity: 1, y: 0 }}>
            ${money(total)}
          </motion.b>
          <span className="wal-bal-toks">
            <UsdcIcon className="tok" />
            <span>{money(w.usdc)}</span>
            <SolIcon className="tok" />
            <span>{w.sol.toFixed(2)}</span>
          </span>
        </div>

        {w.tab === "send" ? (
          w.stage === "sending" ? (
            <ol className="wal-steps">
              {steps.map(([title, by], i) => (
                <motion.li key={title} className={cx(w.step > i && "done", w.step === i && "now")} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.08 }}>
                  <span className="wal-step-dot">{w.step > i ? <I.CheckIcon /> : null}</span>
                  <b>{title}</b>
                  <span className="wal-step-by">
                    {by === "magicblock" ? <MagicBlockLogo className="mb-logo" /> : by === "settled on Solana" ? <>settled on <SolIcon className="tok sm" /></> : by}
                  </span>
                </motion.li>
              ))}
            </ol>
          ) : (
            <>
              <div className="wal-row">
                <b className="wal-amt kb-num">${w.amount}</b>
                <span className="tok-chip">{w.token === "SOL" ? <SolIcon className="tok" /> : <UsdcIcon className="tok" />}{w.token}</span>
                <span className="wal-arrow">→</span>
                <span className="wal-to">
                  {w.name && <b>{w.name}</b>}
                  <span>{w.to ? shortAddr(w.to) : "Paste an address"}</span>
                </span>
              </div>
              <button type="button" className={cx("wal-priv", w.private && "on", co("wallet:private"))} onClick={() => perform("wallet:private")}>
                <MagicBlockMark className="mb-mark" />
                <span className="wal-priv-label">
                  <b>Private</b>
                  <MagicBlockLogo className="mb-logo" />
                </span>
                <span className="wal-switch" aria-hidden />
              </button>
              <button type="button" className={cx("wal-go", co("wallet:send"))} onClick={() => perform("wallet:send")} disabled={!w.to}>
                {w.private ? "Send privately" : "Send"}
                {tip("wallet:send")}
              </button>
            </>
          )
        ) : (
          <>
            <div className="swap">
              <div className="swap-row">
                <span className="swap-k">Sell</span>
                <b className="kb-num">{sellAmt}</b>
                <span className="tok-chip">{sellTok === "SOL" ? <SolIcon className="tok" /> : <UsdcIcon className="tok" />}{sellTok}</span>
              </div>
              <button type="button" className="swap-flip" onClick={() => perform("swap:flip")} aria-label="Flip">
                <I.SwapIcon />
              </button>
              <div className="swap-row">
                <span className="swap-k">Buy</span>
                <b className="kb-num">≈ {buyAmt}</b>
                <span className="tok-chip">{buyTok === "SOL" ? <SolIcon className="tok" /> : <UsdcIcon className="tok" />}{buyTok}</span>
              </div>
            </div>
            <p className="swap-meta">1 SOL ≈ {SWAP_RATE} USDC · best route via Jupiter</p>
            <button type="button" className={cx("wal-go", w.swap === "done" && "ok")} onClick={() => perform("swap:go")}>
              {w.swap === "swapping" ? "Swapping…" : w.swap === "done" ? "Swapped ✓" : "Swap"}
            </button>
          </>
        )}
      </div>
    );
  };

  const renderPanel = () => {
    switch (s.panel) {
      case "wallet":
        return renderWallet();
      case "menu":
        return (
          <div className="kb-menu">
            {MENU.map((m, i) => (
              <motion.button key={m.id} type="button" className={cx("kb-tile", co(`menu:${m.id}`))} onClick={() => perform(`menu:${m.id}`)} initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} transition={{ duration: 0.3, delay: i * 0.03, ease }}>
                <m.Icon />
                <span>{m.label}</span>
                {tip(`menu:${m.id}`)}
              </motion.button>
            ))}
          </div>
        );
      case "search":
        if (s.searchView === "suggest") {
          return (
            <div className="kb-rows">
              {SEARCH_SUGGEST[s.tab].map((q, i) => (
                <motion.button key={`${s.tab}-${q}`} type="button" className={cx("kb-row kb-row--sugg", co(`sugg:${i}`))} onClick={() => perform(`sugg:${i}`)} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35, delay: i * 0.05, ease }}>
                  {s.tab === "maps" ? <I.PinIcon /> : s.tab === "youtube" ? <I.PlayRectIcon /> : <I.SearchIcon />}
                  <span className="kb-row-v strong">{q}</span>
                  {tip(`sugg:${i}`)}
                </motion.button>
              ))}
            </div>
          );
        }
        return s.searching ? (
          <div className="kb-cards"><span className="kb-card kb-skel" /><span className="kb-card kb-skel" /></div>
        ) : (
          <div className="kb-cards">{(s.results ?? []).map((c, i) => renderCard(c, `card:${i}`, i))}</div>
        );
      case "vault":
        return (
          <div className="kb-vault">
            {VAULT.map((v, i) => (
              <motion.button key={v.id} type="button" className={cx("kb-vcard", co(`vault:${v.id}`))} onClick={() => perform(`vault:${v.id}`)} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: i * 0.035, ease }}>
                <span className="kb-vcard-k">{v.label}</span>
                <span className="kb-vcard-v">{short(v)}</span>
                {tip(`vault:${v.id}`)}
              </motion.button>
            ))}
          </div>
        );
      case "clip":
        return (
          <div className="kb-rows">
            {CLIPS.map((c, i) => (
              <button key={c} type="button" className="kb-row" onClick={() => perform(`clip:${i}`)}>
                <span className="kb-row-k">{CLIP_AGE[i]}</span>
                <span className="kb-row-v">{c}</span>
              </button>
            ))}
          </div>
        );
      case "emoji":
        return (
          <div className="kb-emoji">
            {EMOJI.map((e, i) => (
              <button key={e} type="button" onClick={() => perform(`emoji:${i}`)} aria-label={`Insert ${e}`}>{e}</button>
            ))}
          </div>
        );
      case "tones":
        return (
          <div className="kb-rows">
            {TONES.map((t) => (
              <button key={t.id} type="button" className={cx("kb-row", co(`tone:${t.id}`))} onClick={() => perform(`tone:${t.id}`)} disabled={!s.text.trim()}>
                <span className="kb-row-k">{t.label}</span>
                <span className="kb-row-v">{s.text.trim() ? rewrite(s.text, t.id) : "—"}</span>
                {tip(`tone:${t.id}`)}
              </button>
            ))}
          </div>
        );
      case "act":
        return renderAct();
      case "skills":
        return (
          <div className="kb-rows">
            {Object.entries(SKILLS).map(([k, v]) => (
              <button key={k} type="button" className="kb-row" onClick={() => perform(`skill:${k}`)}>
                <span className="kb-cap">{k}<span className="kb-dot" /></span>
                <span className="kb-row-k">{v.name}</span>
                <span className="kb-row-v">{v.hint}</span>
              </button>
            ))}
          </div>
        );
    }
    return null;
  };

  const rows = s.mode === "abc" ? ROWS_ABC : ROWS_123;
  const text = s.text;
  const flash = s.flash && s.flash.at + s.flash.len <= text.length ? s.flash : null;
  const typingQuery = s.panel === "search" && s.searchView === "type";
  const caret = !typingQuery && <span className="kb-caret" />;

  return (
    <div
      ref={root}
      className={cx("kb", s.ai && "is-ai")}
      onPointerDown={engage}
    >
      <div className="im-inputbar">
        <button type="button" className={cx("im-plus", co("g"))} aria-label="Glyf menu" onClick={() => perform("g")}>
          <I.PlusIcon />
        </button>
        <div className="im-field">
          <div className="im-text">
            <span className="im-text-in">
              {text ? (
                <motion.span key={draftId} layoutId={draftId} className="im-draft">
                  {flash ? (
                    <>
                      {text.slice(0, flash.at)}
                      <mark key={flash.id} className="kb-mark">{text.slice(flash.at, flash.at + flash.len)}</mark>
                      {text.slice(flash.at + flash.len)}
                    </>
                  ) : (
                    text
                  )}
                  {caret}
                </motion.span>
              ) : (
                <>
                  {caret}
                  <span className="ph">iMessage</span>
                </>
              )}
            </span>
          </div>
          <AnimatePresence initial={false} mode="popLayout">
            {text.trim() ? (
              <motion.button
                key="send"
                type="button"
                className={cx("im-send", co("send"))}
                aria-label="Send"
                onPointerDown={(e) => {
                  e.preventDefault();
                  engage();
                }}
                onClick={send}
                initial={{ scale: 0.4, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0.4, opacity: 0 }}
                transition={{ type: "spring", stiffness: 520, damping: 30 }}
              >
                <I.ArrowUpIcon />
                {tip("send")}
              </motion.button>
            ) : (
              <motion.span key="mic" className="im-mic" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                <I.MicIcon />
              </motion.span>
            )}
          </AnimatePresence>
        </div>
      </div>

      <div className="kb-slab">
        <div className="kb-strip">
          {s.panel ? (
            <button type="button" className={cx("kb-side kb-close", co("close"))} aria-label="Close" onClick={() => perform("close")}>
              <I.CloseIcon />
              {tip("close")}
            </button>
          ) : (
            <button type="button" className={cx("kb-side kb-g", co("g"))} aria-label="Glyf menu" onClick={() => perform("g")}>
              g<span className="kb-gdot" />
            </button>
          )}
          <div className="kb-strip-main">{renderStrip()}</div>
        </div>
        <div className="kb-body">
          <div className={cx("kb-keys", covering && "is-covered")} aria-hidden={covering}>
            {rows[0].map((k) => renderKey(k, 0))}
            {rows[1].map((k, i) => renderKey(k, 1, { start: s.mode === "abc" && i === 0 ? 2 : undefined }))}
            {renderKey("shift", 2, { span: 3, fn: true, label: <I.ShiftIcon on={s.shift} />, aria: "Shift", cls: s.shift ? "on" : "" })}
            {rows[2].map((k) => renderKey(k, 2))}
            {renderKey("backspace", 2, { span: 3, fn: true, label: <I.BackspaceIcon />, aria: "Delete" })}
            {renderKey("mode", 3, { span: 3, fn: true, label: s.mode === "abc" ? "123" : "ABC", aria: "Switch keys" })}
            {renderKey("emoji", 3, { span: 2, fn: true, label: <I.EmojiIcon />, aria: "Emoji" })}
            {renderKey("space", 3, { span: 10, label: <span className="kb-space-mark">glyf</span>, aria: "Space — hold for Glyf", cls: "space" })}
            {renderKey(".", 3, { span: 2, fn: true, aria: "Full stop" })}
            {renderKey("return", 3, { span: 3, fn: true, label: <I.ReturnIcon />, aria: "Return" })}
          </div>
          <AnimatePresence>
            {covering && (
              <motion.div
                key={`${s.panel}-${s.panel === "search" ? s.searchView : ""}`}
                className="kb-panel"
                initial={{ opacity: 0, y: 26 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 14 }}
                transition={{ type: "spring", stiffness: 380, damping: 34 }}
              >
                {renderPanel()}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
