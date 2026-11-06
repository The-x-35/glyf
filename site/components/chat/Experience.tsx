"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import { solAddress } from "../kb/data";
import { MagicBlockLogo, SolIcon, UsdcIcon } from "../kb/brands";
import Keyboard, { MiniMap, type KbSnapshot, type KeyboardApi } from "../kb/Keyboard";
import { LockIcon, SearchIcon } from "../kb/icons";
import { SCENARIOS, type Scenario } from "./scenarios";

/** The chats, as iMessage: on a laptop the chat list sits beside the window;
 *  on a phone it's the conversation, with Messages one tap back. */

export type Msg = { id: string; from: "me" | "them"; text: string; at: string; layoutId?: string; tapback?: string; copyable?: boolean };

type Thread = {
  msgs: Msg[];
  beat: number;
  typing: boolean;
  waiting: boolean;
  done: boolean;
  status: "Delivered" | "Read" | null;
};

const N = SCENARIOS.length;

/** How many steps the stage's scroll is cut into.
 *
 *  The stage is a timeline, not a list of chats: ONE step of scroll performs
 *  ONE action — tap the key the coach is pointing at, or, when a chat is
 *  finished, open the next one. Scroll used to address the CHAT instead
 *  (`floor(progress × chats)`), which is why it would leave for the next
 *  conversation in the middle of the one you were doing.
 *
 *  Run straight through, the eight chats take about fifty steps (Daniel's
 *  calendar added six to the seven's forty-five, measured by scrolling the
 *  whole stage a notch at a time). The rest is slack for a
 *  visitor who goes their own way: opening a panel they then close costs two,
 *  and an answer the friend nudges back costs a couple more. Each tick is
 *  nine hundredths of the viewport, near enough one notch of a wheel that a
 *  notch does one thing.
 */
const TICKS = 80;

const ease = [0.22, 1, 0.36, 1] as const;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
let seq = 0;
const uid = () => `m${Date.now().toString(36)}${(seq++).toString(36)}`;
const hash = (s: string) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
const clock = () => new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date());
const EARLIER = ["9:41 AM", "9:38 AM", "9:30 AM", "9:12 AM", "8:55 AM", "8:20 AM", "Yesterday", "Yesterday"];

/** What a chat shows before it's opened: the friend's ask, not a pasted wallet address. */
const teaser = (sc: Scenario) => {
  const lines = sc.beats[0].them;
  return [...lines].reverse().find((l) => !solAddress(l)) ?? lines[lines.length - 1];
};

export const Done = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" aria-label="Done">
    <circle cx="10" cy="10" r="9" fill="#34c759" />
    <path d="m6 10.2 2.6 2.6L14 7.4" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const Back = () => (
  <svg viewBox="0 0 12 20" width="12" height="20" aria-hidden>
    <path d="M10 2 2 10l8 8" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const Video = () => (
  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden>
    <rect x="2.5" y="6" width="13" height="12" rx="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
    <path d="m15.5 10.2 5-3v9.6l-5-3z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
  </svg>
);

/** The autopilot's pointer: a Mac arrow on desktop, a fingertip on touch. */
export const Arrow = () => (
  <svg viewBox="0 0 24 28" width="24" height="28" aria-hidden>
    <path d="M3 2v19.5l5-4.6 3.3 7.1 3.1-1.4-3.2-6.9 6.8-.4z" fill="#fff" stroke="#111" strokeWidth="1.4" strokeLinejoin="round" />
  </svg>
);

const Chevron = () => (
  <svg viewBox="0 0 8 14" width="8" height="14" aria-hidden>
    <path d="m1 1 6 6-6 6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export function Avatar({ sc, size = "md" }: { sc: Scenario; size?: "sm" | "md" | "lg" }) {
  return (
    <span className={cx("av", `av--${size}`)} style={{ "--tint": sc.tint } as CSSProperties} aria-hidden>
      {sc.avatar}
    </span>
  );
}

/** Links become cards, the way both apps render them. */
function Rich({ text }: { text: string }) {
  if (text.startsWith("💸 ")) {
    const [amount, rest = ""] = text.slice(3).split(" · ");
    const hidden = /privately/.test(rest);
    return (
      <span className="rich pay">
        <span className="pay-top">
          {hidden ? <LockIcon /> : null}
          {hidden ? "Sent privately" : "Sent"}
        </span>
        <b className="pay-amt">
          {amount.replace(/ (USDC|SOL)$/, "")}
          <span className="pay-tok">
            {/SOL$/.test(amount) ? <SolIcon className="tok" /> : <UsdcIcon className="tok" />}
            {/SOL$/.test(amount) ? "SOL" : "USDC"}
          </span>
        </b>
        <span className="pay-meta">
          <SolIcon className="tok sm" /> Solana
          {hidden && (
            <>
              <span className="pay-dot">·</span>
              <MagicBlockLogo className="mb-logo" />
            </>
          )}
        </span>
      </span>
    );
  }
  if (text.startsWith("📍 ")) {
    const [name, dist] = text.slice(3).split(" · ");
    return (
      <span className="rich">
        <MiniMap seed={hash(name)} />
        <span className="rich-body">
          <b>{name}</b>
          <span>{dist ? `${dist} · Maps` : "Maps"}</span>
        </span>
      </span>
    );
  }
  if (text.startsWith("▶ ")) {
    const title = text.slice(2);
    return (
      <span className="rich">
        <span className="rich-thumb" style={{ "--h": hash(title) % 360 } as CSSProperties}>
          <span className="rich-play" />
        </span>
        <span className="rich-body">
          <b>{title}</b>
          <span>youtube.com</span>
        </span>
      </span>
    );
  }
  return null;
}

export function Bubble({
  m, first, last, coach, menuOpen, onTap, onCopy,
}: {
  m: Msg;
  first: boolean;
  last: boolean;
  coach: { target: string; label: string } | null;
  menuOpen: boolean;
  onTap: () => void;
  onCopy: () => void;
}) {
  const mine = m.from === "me";
  const rich = Rich({ text: m.text });
  const coachBubble = m.copyable && coach?.target === "bubble:addr";
  const coachCopy = menuOpen && coach?.target === "bubble:copy";
  return (
    <div className={cx("msg", mine ? "me" : "them", first && "first", last && "last", m.tapback && "has-tap", menuOpen && "menu-open")}>
      <motion.div
        layoutId={m.layoutId}
        className={cx("bub", rich && "bub--rich", rich && m.text.startsWith("💸") && "bub--pay", m.layoutId && "sent", m.copyable && "copyable", coachBubble && "is-coach")}
        initial={m.layoutId ? false : { opacity: 0, scale: 0.6, y: 12 }}
        animate={{ opacity: 1, scale: menuOpen ? 1.03 : 1, y: 0 }}
        transition={{ type: "spring", stiffness: 480, damping: 32, mass: 0.8 }}
        style={{ originX: mine ? 1 : 0, originY: 1 }}
        onClick={m.copyable ? onTap : undefined}
        role={m.copyable ? "button" : undefined}
        tabIndex={m.copyable ? 0 : undefined}
      >
        {rich}
        {!rich && <motion.span layout="position" className="bub-text">{m.text}</motion.span>}
        {coachBubble && <span className="kb-coach">{coach!.label}</span>}
        <AnimatePresence>
          {m.tapback && (
            <motion.span
              className="tapback"
              initial={{ scale: 0, rotate: -40, opacity: 0 }}
              animate={{ scale: 1, rotate: 0, opacity: 1 }}
              transition={{ type: "spring", stiffness: 520, damping: 16 }}
            >
              {m.tapback}
            </motion.span>
          )}
        </AnimatePresence>
      </motion.div>
      <AnimatePresence>
        {menuOpen && (
          <motion.div
            className="bub-menu"
            initial={{ opacity: 0, scale: 0.85, y: 8 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 6 }}
            transition={{ type: "spring", stiffness: 520, damping: 30 }}
          >
            <button type="button" className={cx("bub-menu-item", coachCopy && "is-coach")} onClick={onCopy}>
              Copy
              {coachCopy && <span className="kb-coach">{coach!.label}</span>}
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export default function Experience() {
  const section = useRef<HTMLElement>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const [threads, setThreads] = useState<Record<string, Thread>>(() =>
    Object.fromEntries(SCENARIOS.map((s) => [s.id, { msgs: [], beat: 0, typing: false, waiting: true, done: false, status: null }])),
  );
  const [snap, setSnap] = useState<KbSnapshot | null>(null);
  const [draftId, setDraftId] = useState(() => `d-${uid()}`);
  const [seed, setSeed] = useState<{ key: string; text?: string; lang?: "hi" | "es" | "fr"; pay?: Scenario["beats"][number]["pay"] }>({ key: "init" });
  const [autotype, setAutotype] = useState<{ key: string; text: string } | null>(null);
  const [banner, setBanner] = useState<number | null>(null);
  const [listOpen, setListOpen] = useState(false);
  const [menu, setMenu] = useState<string | null>(null);
  const [copied, setCopied] = useState<{ key: string; text: string } | null>(null);
  const appRef = useRef<HTMLDivElement>(null);

  const threadsRef = useRef(threads);
  const activeRef = useRef(active);
  activeRef.current = active;
  const started = useRef(new Set<string>());
  const pending = useRef(new Map<string, Msg>());
  const autoAt = useRef(0);

  // The scroll timeline. `spent` is how many steps the demo has actually
  // taken — by the visitor's own hand or the pointer's — and `want` is how
  // many the scroll has paid for. Whenever want runs ahead, the pointer
  // performs the next one; whenever the visitor runs ahead, the scroll is
  // wound forward to meet them, which costs nothing to look at because the
  // stage is pinned and nothing on it moves with the page.
  const kbApi = useRef<KeyboardApi>(null);
  const coachRef = useRef<ReturnType<Scenario["beats"][number]["coach"]>>(null);
  const spent = useRef(0);
  const want = useRef(0);
  const inStage = useRef(false);
  const piloting = useRef(false);
  const [ghost, setGhost] = useState({ x: 0, y: 0, show: false, press: false });

  const copyAddress = (visitor: boolean) => {
    const msgs = threadsRef.current[SCENARIOS[activeRef.current].id].msgs;
    const m = [...msgs].reverse().find((x) => x.copyable);
    if (!m) return;
    setMenu(null);
    setCopied({ key: uid(), text: m.text });
    if (visitor) navigator.clipboard?.writeText(m.text).catch(() => {});
  };

  const openCopyMenu = () => {
    const msgs = threadsRef.current[SCENARIOS[activeRef.current].id].msgs;
    const m = [...msgs].reverse().find((x) => x.copyable);
    if (m) setMenu(m.id);
  };

  const hideGhost = () => setGhost((g) => (g.show ? { ...g, show: false, press: false } : g));

  /** Wind the page forward to the step the demo has actually reached.
   *
   *  Only ever forward, and only while the stage is pinned — where the page
   *  moving changes nothing on screen. This is what keeps a visitor who does
   *  the tapping themselves from then having to scroll back through the
   *  stretch of page their own taps already paid for. */
  const syncScroll = () => {
    const el = section.current;
    if (!el || !inStage.current) return;
    const span = el.offsetHeight - window.innerHeight;
    if (span <= 0) return;
    const top = el.getBoundingClientRect().top + window.scrollY;
    const to = top + (span * Math.min(spent.current, TICKS)) / TICKS;
    if (to <= window.scrollY + 1) return;
    window.scrollTo({ top: to });
    // Keep the two in step without waiting on the scroll event, so the next
    // notch is the next action rather than a repeat of this one.
    want.current = Math.min(spent.current, TICKS);
  };

  /** Take the next step, if the scroll has paid for one and there is one to
   *  take. Nothing is forced: while the friend is still typing there is no
   *  action to perform, so the step stays bought and happens the moment the
   *  chat is ready — which is what stops a fast scroll from skidding past a
   *  reply the visitor never saw. */
  const pump = () => {
    if (piloting.current || !inStage.current) return;
    if (want.current <= spent.current) return hideGhost();
    const i = activeRef.current;
    const t = threadsRef.current[SCENARIOS[i].id];
    // A finished chat: this step opens the next one.
    if (t.done) {
      if (i + 1 >= N) return hideGhost();
      piloting.current = true;
      hideGhost();
      setActive(i + 1);
      window.setTimeout(() => {
        piloting.current = false;
        pump();
      }, 260);
      return;
    }
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const c = coachRef.current;
    const el = appRef.current?.querySelector<HTMLElement>(".is-coach") ?? kbApi.current?.target();
    if (!c || !el || t.waiting) return;
    piloting.current = true;
    // Behind by more than a step means the visitor is scrolling quickly; the
    // pointer stops explaining itself and just keeps up.
    const hurry = want.current - spent.current > 1;
    void (async () => {
      const r = el.getBoundingClientRect();
      setGhost((g) => ({
        x: r.left + r.width / 2,
        y: r.top + r.height / 2,
        show: true,
        press: false,
        ...(g.show ? {} : { x: r.left + r.width / 2 + 120, y: r.top + r.height / 2 + 90 }),
      }));
      if (!ghostShown.current) {
        ghostShown.current = true;
        await sleep(60);
        setGhost((g) => ({ ...g, x: r.left + r.width / 2, y: r.top + r.height / 2 }));
      }
      await sleep(hurry ? 180 : 560);
      if (activeRef.current !== i || coachRef.current?.target !== c.target) {
        piloting.current = false;
        return pump();
      }
      setGhost((g) => ({ ...g, press: true }));
      if (c.target === "bubble:addr") openCopyMenu();
      else if (c.target === "bubble:copy") copyAddress(false);
      else await kbApi.current?.run(c.target, /^hold/i.test(c.label));
      await sleep(160);
      setGhost((g) => ({ ...g, press: false }));
      await sleep(hurry ? 140 : 320);
      piloting.current = false;
      pump();
    })();
  };
  const ghostShown = useRef(false);

  /** How far through the stage the page is, 0 to 1 — read off the section
   *  itself rather than through `useScroll`.
   *
   *  `useScroll` with a `target` measured nothing on a cold load here: the
   *  progress stayed at 0 and its change event never fired, so the timeline
   *  sat still until an edit remounted the component. One rect and one
   *  subtraction have no such opinion about when they are allowed to run. */
  const pumpRef = useRef(pump);
  pumpRef.current = pump;
  useEffect(() => {
    const read = () => {
      const el = section.current;
      const span = el ? el.offsetHeight - window.innerHeight : 0;
      if (!el || span <= 0) return;
      const top = el.getBoundingClientRect().top + window.scrollY;
      const v = (window.scrollY - top) / span;
      inStage.current = v > 0.001 && v < 0.999;
      want.current = Math.round(Math.min(1, Math.max(0, v)) * TICKS);
      if (!inStage.current) return hideGhost();
      pumpRef.current();
    };
    read();
    window.addEventListener("scroll", read, { passive: true });
    window.addEventListener("resize", read);
    return () => {
      window.removeEventListener("scroll", read);
      window.removeEventListener("resize", read);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** Updates are computed eagerly so async flows always read the latest thread. */
  const patch = (id: string, fn: (t: Thread) => Partial<Thread>) => {
    const prev = threadsRef.current;
    const next = { ...prev, [id]: { ...prev[id], ...fn(prev[id]) } };
    threadsRef.current = next;
    setThreads(next);
  };

  const seedFor = (sc: Scenario, t: Thread) => {
    const beat = sc.beats[Math.min(t.beat, sc.beats.length - 1)];
    const ready = !t.waiting && !t.done;
    setSeed({ key: uid(), text: ready ? beat.prefill : undefined, lang: beat.lang, pay: beat.pay });
  };

  const theyType = async (id: string, lines: string[]) => {
    for (const line of lines) {
      patch(id, () => ({ typing: true }));
      await sleep(Math.min(1700, 700 + line.length * 20));
      patch(id, (t) => ({ typing: false, msgs: [...t.msgs, { id: uid(), from: "them", text: line, at: clock(), copyable: solAddress(line) === line.trim() }] }));
      await sleep(420);
    }
  };

  /** The friend is listening again; answer anything sent while they typed. */
  const ready = (index: number) => {
    const sc = SCENARIOS[index];
    patch(sc.id, () => ({ waiting: false }));
    const queued = pending.current.get(sc.id);
    if (queued) {
      pending.current.delete(sc.id);
      judge(index, queued);
    }
  };

  const startBeat = async (index: number, beat: number) => {
    const sc = SCENARIOS[index];
    patch(sc.id, () => ({ beat, waiting: true }));
    await sleep(beat === 0 ? 500 : 300);
    await theyType(sc.id, sc.beats[beat].them);
    const b = sc.beats[beat];
    if (activeRef.current === index && (b.prefill || b.lang)) {
      patch(sc.id, () => ({ waiting: false }));
      seedFor(sc, threadsRef.current[sc.id]);
    }
    ready(index);
  };

  function judge(index: number, msg: Msg) {
    const sc = SCENARIOS[index];
    const th = threadsRef.current[sc.id];
    if (th.done) return;
    const beat = sc.beats[th.beat];
    const ok = beat.goal(msg.text);
    patch(sc.id, () => ({ waiting: true }));
    void (async () => {
      await sleep(850);
      patch(sc.id, () => ({ status: "Read" }));
      await sleep(450);
      if (!ok) {
        await theyType(sc.id, [beat.nudge]);
        if (activeRef.current === index && beat.prefill) {
          patch(sc.id, () => ({ waiting: false }));
          seedFor(sc, threadsRef.current[sc.id]);
        }
        return ready(index);
      }
      if (beat.tapback) {
        patch(sc.id, (t) => ({ msgs: t.msgs.map((m) => (m.id === msg.id ? { ...m, tapback: beat.tapback } : m)) }));
        await sleep(650);
      }
      await theyType(sc.id, typeof beat.reply === "function" ? beat.reply(msg.text) : beat.reply);
      if (th.beat + 1 < sc.beats.length) {
        await startBeat(index, th.beat + 1);
      } else {
        patch(sc.id, () => ({ done: true, waiting: false }));
        await sleep(700);
        if (activeRef.current === index) setBanner(index + 1 < N ? index + 1 : -1);
      }
    })();
  }

  useEffect(() => {
    const sc = SCENARIOS[active];
    setBanner(null);
    setAutotype(null);
    setListOpen(false);
    setMenu(null);
    seedFor(sc, threadsRef.current[sc.id]);
    if (!started.current.has(sc.id)) {
      started.current.add(sc.id);
      void startBeat(active, 0);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active]);

  // Banners slide away like iOS ones, so they never park on the back button.
  useEffect(() => {
    if (banner === null) return;
    const id = window.setTimeout(() => setBanner(null), 6000);
    return () => clearTimeout(id);
  }, [banner]);

  const onSend = (text: string, layoutId: string) => {
    const index = activeRef.current;
    const sc = SCENARIOS[index];
    const th = threadsRef.current[sc.id];
    const msg: Msg = { id: uid(), from: "me", text, at: clock(), layoutId };
    patch(sc.id, (t) => ({ msgs: [...t.msgs, msg], status: "Delivered" }));
    setDraftId(`d-${uid()}`);
    if (th.done) return;
    if (th.waiting) pending.current.set(sc.id, msg);
    else judge(index, msg);
  };

  /** The chat list is a shortcut, not a scroll position: the timeline runs on
   *  steps now, so picking a chat just opens it and scrolling carries on from
   *  there. (It used to scroll to that chat's slice of the page, which is the
   *  same arithmetic that made plain scrolling leave a chat unfinished.) */
  const jump = (i: number) => {
    setListOpen(false);
    hideGhost();
    setActive(i);
  };

  const sc = SCENARIOS[active];
  const th = threads[sc.id];
  const beatNow = sc.beats[Math.min(th.beat, sc.beats.length - 1)];
  const coach = !th.waiting && !th.done && snap && !snap.auto ? beatNow.coach(snap, { menu, copied: copied?.text ?? null }) : null;
  coachRef.current = coach;

  /** The one action the stage is waiting on: what the coach is pointing at,
   *  or the chat being finished. It is null while the friend is typing —
   *  there is nothing to do then, and nothing to charge for.
   *
   *  Landing on a NEW one of these is a step, whoever caused it. That is the
   *  whole timeline: the visitor doing it themselves and the pointer doing it
   *  for them are the same event, so the two can never disagree about how far
   *  along the demo is. */
  const stepKey = th.done ? `${active}:done` : coach ? `${active}:${th.beat}:${coach.target}` : null;
  const lastStep = useRef<string | null>(null);
  useEffect(() => {
    if (stepKey === null || stepKey === lastStep.current) return;
    const opening = lastStep.current === null;
    lastStep.current = stepKey;
    if (!opening) spent.current += 1;
    // The visitor got here on their own, so bring the page with them.
    if (!piloting.current) syncScroll();
    const id = window.setTimeout(pump, 200);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stepKey]);

  // A chat that has just become ready may owe the visitor a step they have
  // already scrolled for.
  useEffect(() => {
    const id = window.setTimeout(pump, 220);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [th.waiting, th.typing, active]);
  const lastMsg = th.msgs[th.msgs.length - 1];
  const unread = SCENARIOS.filter((c, i) => i !== active && !threads[c.id].done).length;

  // Typing is the keyboard's job: once the friend has asked, it types for you.
  useEffect(() => {
    const at = beatNow.autotype;
    if (!at || !snap || th.waiting || th.done || snap.auto) return;
    const text = at(snap);
    if (!text) return;
    if (Date.now() - autoAt.current < 900) return;
    autoAt.current = Date.now();
    setAutotype({ key: uid(), text });
  }, [snap, th.waiting, th.done, beatNow]);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [th.msgs.length, th.typing, active, th.status]);

  const rows = (variant: "desk" | "mob") =>
    SCENARIOS.map((c, i) => {
      const t = threads[c.id];
      const last = t.msgs[t.msgs.length - 1];
      const preview = last ? (last.from === "me" && variant === "desk" ? `You: ${last.text}` : last.text) : teaser(c);
      const pendingChat = !t.done && i !== active;
      return (
        <li key={c.id}>
          <button type="button" className={cx("row", i === active && "on", t.done && "done")} onClick={() => jump(i)} aria-current={i === active}>
            {variant === "desk" && i === active && <motion.span layoutId="row-on" className="row-bg" transition={{ type: "spring", bounce: 0.15, duration: 0.5 }} />}
            <span className="row-dot" data-on={pendingChat || undefined} />
            <Avatar sc={c} />
            <span className="row-main">
              <span className="row-top">
                <b>{c.name}</b>
                {variant === "desk" ? <span className="row-tag">{c.tag}</span> : <span className="row-time">{last ? last.at : EARLIER[i]}</span>}
                {variant === "mob" && (
                  <span className="row-chev">
                    <Chevron />
                  </span>
                )}
              </span>
              <span className="row-prev">{preview}</span>
            </span>
            {variant === "desk" && <span className="row-end">{t.done ? <Done /> : null}</span>}
          </button>
        </li>
      );
    });

  return (
    <section ref={section} className="xp" style={{ "--ticks": TICKS } as CSSProperties} aria-label="Try Glyf">
      <div className="xp-pin">
        <div className="wrap xp-grid">
          <div className="xp-head">
            <AnimatePresence mode="popLayout" initial={false}>
              <motion.h2
                key={sc.id}
                className="xp-headline"
                initial={{ opacity: 0, y: 30, filter: "blur(10px)" }}
                animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                exit={{ opacity: 0, y: -30, filter: "blur(10px)" }}
                transition={{ duration: 0.6, ease }}
              >
                <span>{sc.headline[0]}</span> <span>{sc.headline[1]}</span>
              </motion.h2>
            </AnimatePresence>
          </div>

          <ol className="xp-list only-desk" aria-label="Chats">
            {rows("desk")}
          </ol>

          <div
            ref={appRef}
            className="app"
            data-list={listOpen ? "open" : "closed"}
            // The visitor's own hand: the pointer gets out of the way, and the
            // step they are about to take is counted by `stepKey` like any other.
            onPointerDownCapture={(e) => {
              if (e.isTrusted) hideGhost();
            }}
          >
            {/* Phones: the Messages screen, one tap back from the conversation */}
            <aside className="app-side only-mob" aria-label="Messages">
              <b className="side-title">Messages</b>
              <ol className="side-list">{rows("mob")}</ol>
              <div className="side-search">
                <SearchIcon />
                <span>Search</span>
              </div>
            </aside>

            <main className="app-chat">
              <header className="chat-head">
                <button type="button" className="chat-back only-mob" onClick={() => setListOpen(true)} aria-label="All chats">
                  <Back />
                  {unread > 0 && <span className="chat-back-count">{unread}</span>}
                </button>
                <AnimatePresence mode="popLayout" initial={false}>
                  <motion.div key={sc.id} className="chat-who" initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 6 }} transition={{ duration: 0.3, ease }}>
                    <Avatar sc={sc} size="sm" />
                    <span className="chat-name">
                      <b>{sc.name}</b>
                      <span className="chat-name-chev">
                        <Chevron />
                      </span>
                    </span>
                  </motion.div>
                </AnimatePresence>
                <span className="chat-actions">
                  <span className="chat-icon">
                    <Video />
                  </span>
                </span>
              </header>

              <AnimatePresence>
                {banner !== null && (
                  <motion.button
                    type="button"
                    className="banner"
                    initial={{ opacity: 0, y: -40, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -30 }}
                    transition={{ type: "spring", stiffness: 380, damping: 30 }}
                    onClick={() => (banner === -1 ? document.getElementById("join")?.scrollIntoView({ behavior: "smooth" }) : jump(banner))}
                  >
                    {banner === -1 ? (
                      <>
                        <span className="av av--sm av--glyf">g</span>
                        <span className="banner-body">
                          <b>Glyf</b>
                          <span>That&apos;s everyone. Get Glyf first →</span>
                        </span>
                      </>
                    ) : (
                      <>
                        <Avatar sc={SCENARIOS[banner]} size="sm" />
                        <span className="banner-body">
                          <b>{SCENARIOS[banner].name}</b>
                          <span>{teaser(SCENARIOS[banner])}</span>
                        </span>
                        <span className="banner-time">now</span>
                      </>
                    )}
                  </motion.button>
                )}
              </AnimatePresence>

              <motion.div ref={scroller} className="thread" layoutScroll>
                <AnimatePresence mode="wait" initial={false}>
                  <motion.div key={sc.id} className="thread-in" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }} transition={{ duration: 0.28, ease }}>
                    <p className="day">
                      <b>Today</b> {th.msgs[0]?.at ?? "9:41 AM"}
                    </p>
                    {th.msgs.map((m, i) => {
                      const prev = th.msgs[i - 1];
                      const next = th.msgs[i + 1];
                      return (
                        <Bubble
                          key={m.id}
                          m={m}
                          first={!prev || prev.from !== m.from}
                          last={!next || next.from !== m.from}
                          coach={coach}
                          menuOpen={menu === m.id}
                          onTap={() => setMenu((x) => (x === m.id ? null : m.id))}
                          onCopy={() => copyAddress(true)}
                        />
                      );
                    })}
                    {lastMsg?.from === "me" && th.status && (
                      <motion.p key={th.status} className="receipt" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.2 }}>
                        {th.status}
                      </motion.p>
                    )}
                    <AnimatePresence>
                      {th.typing && (
                        <motion.div
                          className="msg them first last typing-row"
                          initial={{ opacity: 0, scale: 0.6 }}
                          animate={{ opacity: 1, scale: 1 }}
                          exit={{ opacity: 0, scale: 0.6 }}
                          transition={{ type: "spring", stiffness: 500, damping: 30 }}
                          style={{ originX: 0, originY: 1 }}
                        >
                          <div className="bub typing">
                            <i />
                            <i />
                            <i />
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </motion.div>
                </AnimatePresence>
              </motion.div>

              <Keyboard
                seed={seed}
                draftId={draftId}
                coach={coach}
                autotype={autotype}
                chips={th.done ? null : beatNow.chips ?? null}
                copied={copied}
                onSend={onSend}
                onSnapshot={setSnap}
                apiRef={kbApi}
                privateAI={!!beatNow.zeroG}
              />
            </main>
          </div>
        </div>
      </div>
      <motion.div
        className={cx("ghost", ghost.press && "press")}
        initial={false}
        animate={{ x: ghost.x, y: ghost.y, opacity: ghost.show ? 1 : 0 }}
        transition={{ x: { type: "spring", stiffness: 140, damping: 22 }, y: { type: "spring", stiffness: 140, damping: 22 }, opacity: { duration: 0.25 } }}
        aria-hidden
      >
        <span className="ghost-ring" />
        <Arrow />
      </motion.div>
    </section>
  );
}
