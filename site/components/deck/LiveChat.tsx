"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import { solAddress } from "../kb/data";
import Keyboard, { type KbSnapshot, type KeyboardApi } from "../kb/Keyboard";
import { Arrow, Avatar, Bubble, type Msg } from "../chat/Experience";
import type { Scenario } from "../chat/scenarios";

/** One chat from the site, on a clock instead of the scroll: a pointer plays
 *  it through by itself, and the moment the viewer touches anything the chat
 *  is theirs. Finished autoplays loop; a played chat offers a replay. */

type Thread = { msgs: Msg[]; beat: number; typing: boolean; waiting: boolean; done: boolean; status: "Delivered" | "Read" | null };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
let seq = 0;
const uid = () => `l${Date.now().toString(36)}${(seq++).toString(36)}`;
const clock = () => new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date());

type Props = { scenario: Scenario; capture?: boolean };

/** The screen each chat is about: a capture stops here, with the Glyf surface open. */
const MONEY_SHOT: Record<string, (k: KbSnapshot) => boolean> = {
  neha: (k) => k.act === "rewrite",
  sakshi: (k) => k.panel === "search" && k.tab === "maps" && k.results > 0,
  kabir: (k) => k.panel === "search" && k.tab === "google" && k.results > 0,
  mumma: (k) => k.panel === "vault",
  zoya: (k) => k.mine === "upi",
  rohan: (k) => /definately$/i.test(k.text),
  sofia: (k) => k.panel === "translate" && k.translation === "hasta mañana",
  semi: (k) => k.wallet?.tab === "send" && k.wallet.stage === "form",
};

/** How long the live autoplay lingers on an open Glyf screen before acting. */
const dwell = (k: KbSnapshot | null) => (k && (k.panel || k.act || k.wallet || k.calc || k.mine) ? 1700 : 0);

export default function LiveChat({ scenario, capture = false }: Props) {
  const [run, setRun] = useState(0);
  const [mode, setMode] = useState<"auto" | "you">("auto");
  return (
    <div className="lc">
      <Run
        key={run}
        sc={scenario}
        capture={capture}
        onTakeover={() => setMode("you")}
        onLoop={() => setRun((r) => r + 1)}
      />
      {!capture && (
        <div className="lc-bar">
          <span className={cx("lc-state", mode === "you" && "is-you")}>
            <i />
            {mode === "auto" ? "Playing" : "Your turn"}
          </span>
          <button
            type="button"
            className="lc-replay"
            onClick={() => {
              setMode("auto");
              setRun((r) => r + 1);
            }}
          >
            Replay
          </button>
        </div>
      )}
    </div>
  );
}

function Run({ sc, capture, onTakeover, onLoop }: { sc: Scenario; capture: boolean; onTakeover: () => void; onLoop: () => void }) {
  const wrap = useRef<HTMLDivElement>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const kbApi = useRef<KeyboardApi>(null);
  const alive = useRef(true);

  const [th, setTh] = useState<Thread>({ msgs: [], beat: 0, typing: false, waiting: true, done: false, status: null });
  const thRef = useRef(th);
  const [snap, setSnap] = useState<KbSnapshot | null>(null);
  const [draftId, setDraftId] = useState(() => `d-${uid()}`);
  const [seed, setSeed] = useState<{ key: string; text?: string; lang?: "hi" | "es" | "fr"; pay?: Scenario["beats"][number]["pay"] }>({ key: "init" });
  const [autotype, setAutotype] = useState<{ key: string; text: string } | null>(null);
  const [menu, setMenu] = useState<string | null>(null);
  const [copied, setCopied] = useState<{ key: string; text: string } | null>(null);
  const [ghost, setGhost] = useState({ x: 0, y: 0, show: false, press: false });
  const [tick, setTick] = useState(0);
  const acted = useRef(false);
  const frozen = useRef(false);
  const snapRef = useRef<KbSnapshot | null>(null);
  const piloting = useRef(false);
  const pending = useRef<Msg | null>(null);
  const autoAt = useRef(0);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const patch = (fn: (t: Thread) => Partial<Thread>) => {
    if (!alive.current) return;
    const next = { ...thRef.current, ...fn(thRef.current) };
    thRef.current = next;
    setTh(next);
  };

  const seedNow = () => {
    const t = thRef.current;
    const beat = sc.beats[Math.min(t.beat, sc.beats.length - 1)];
    setSeed({ key: uid(), text: !t.waiting && !t.done ? beat.prefill : undefined, lang: beat.lang, pay: beat.pay });
  };

  const theyType = async (lines: string[]) => {
    for (const line of lines) {
      patch(() => ({ typing: true }));
      await sleep(Math.min(1500, 600 + line.length * 18));
      patch((t) => ({ typing: false, msgs: [...t.msgs, { id: uid(), from: "them", text: line, at: clock(), copyable: solAddress(line) === line.trim() }] }));
      await sleep(360);
    }
  };

  const ready = () => {
    patch(() => ({ waiting: false }));
    const q = pending.current;
    if (q) {
      pending.current = null;
      judge(q);
    }
  };

  const startBeat = async (beat: number) => {
    patch(() => ({ beat, waiting: true }));
    await sleep(beat === 0 ? 450 : 280);
    await theyType(sc.beats[beat].them);
    const b = sc.beats[beat];
    if (b.prefill || b.lang) {
      patch(() => ({ waiting: false }));
      seedNow();
    }
    ready();
  };

  function judge(msg: Msg) {
    const t = thRef.current;
    if (t.done) return;
    const beat = sc.beats[t.beat];
    const ok = beat.goal(msg.text);
    patch(() => ({ waiting: true }));
    void (async () => {
      await sleep(750);
      patch(() => ({ status: "Read" }));
      await sleep(400);
      if (!ok) {
        await theyType([beat.nudge]);
        if (beat.prefill) {
          patch(() => ({ waiting: false }));
          seedNow();
        }
        return ready();
      }
      if (beat.tapback) {
        patch((x) => ({ msgs: x.msgs.map((m) => (m.id === msg.id ? { ...m, tapback: beat.tapback } : m)) }));
        await sleep(600);
      }
      await theyType(typeof beat.reply === "function" ? beat.reply(msg.text) : beat.reply);
      if (t.beat + 1 < sc.beats.length) await startBeat(t.beat + 1);
      else patch(() => ({ done: true, waiting: false }));
    })();
  }

  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    seedNow();
    void startBeat(0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A finished autoplay starts over, so a slide left open keeps showing the feature.
  useEffect(() => {
    if (!th.done || acted.current || capture) return;
    setGhost((g) => ({ ...g, show: false }));
    const id = window.setTimeout(onLoop, 3000);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [th.done]);

  const onSend = (text: string, layoutId: string) => {
    const t = thRef.current;
    const msg: Msg = { id: uid(), from: "me", text, at: clock(), layoutId };
    patch((x) => ({ msgs: [...x.msgs, msg], status: "Delivered" }));
    setDraftId(`d-${uid()}`);
    if (t.done) return;
    if (t.waiting) pending.current = msg;
    else judge(msg);
  };

  const copyAddress = (visitor: boolean) => {
    const m = [...thRef.current.msgs].reverse().find((x) => x.copyable);
    if (!m) return;
    setMenu(null);
    setCopied({ key: uid(), text: m.text });
    if (visitor) navigator.clipboard?.writeText(m.text).catch(() => {});
  };

  const beatNow = sc.beats[Math.min(th.beat, sc.beats.length - 1)];
  const coach = !th.waiting && !th.done && snap && !snap.auto ? beatNow.coach(snap, { menu, copied: copied?.text ?? null }) : null;
  const coachRef = useRef(coach);
  coachRef.current = coach;
  snapRef.current = snap;
  if (capture && snap && !frozen.current && MONEY_SHOT[sc.id]?.(snap)) frozen.current = true;

  // The keyboard types for the viewer, exactly as on the site.
  useEffect(() => {
    const at = beatNow.autotype;
    if (!at || !snap || th.waiting || th.done || snap.auto) return;
    const text = at(snap);
    if (!text || Date.now() - autoAt.current < 900) return;
    autoAt.current = Date.now();
    setAutotype({ key: uid(), text });
  }, [snap, th.waiting, th.done, beatNow]);

  // The pointer: walk to whatever the coach points at, press it, repeat.
  useEffect(() => {
    if (acted.current || frozen.current || !coach || piloting.current) return;
    const id = window.setTimeout(() => {
      const c = coachRef.current;
      const box = wrap.current;
      const el = box?.querySelector<HTMLElement>(".is-coach") ?? kbApi.current?.target();
      if (!c || !box || !el || acted.current || piloting.current) return;
      piloting.current = true;
      void (async () => {
        const b = box.getBoundingClientRect();
        const r = el.getBoundingClientRect();
        const x = r.left - b.left + r.width / 2;
        const y = r.top - b.top + r.height / 2;
        setGhost((g) => (g.show ? { x, y, show: true, press: false } : { x: x + 140, y: y + 110, show: true, press: false }));
        await sleep(40);
        setGhost((g) => ({ ...g, x, y }));
        await sleep(760 + (capture ? 0 : dwell(snapRef.current)));
        if (!alive.current || acted.current || frozen.current || coachRef.current?.target !== c.target) {
          piloting.current = false;
          return setTick((n) => n + 1);
        }
        setGhost((g) => ({ ...g, press: true }));
        if (c.target === "bubble:addr") {
          const m = [...thRef.current.msgs].reverse().find((z) => z.copyable);
          if (m) setMenu(m.id);
        } else if (c.target === "bubble:copy") copyAddress(false);
        else await kbApi.current?.run(c.target, /^hold/i.test(c.label));
        await sleep(160);
        setGhost((g) => ({ ...g, press: false }));
        await sleep(380);
        piloting.current = false;
        if (alive.current) setTick((n) => n + 1);
      })();
    }, 520);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coach?.target, coach?.label, th.waiting, tick]);

  const takeOver = () => {
    if (acted.current) return;
    acted.current = true;
    setGhost((g) => ({ ...g, show: false, press: false }));
    onTakeover();
  };

  // Typing on a real keyboard counts as taking over too.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) takeOver();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [th.msgs.length, th.typing, th.status]);

  const lastMsg = th.msgs[th.msgs.length - 1];

  return (
    <div
      ref={wrap}
      className="app lc-app"
      data-list="closed"
      onPointerDownCapture={(e) => {
        if (e.isTrusted) takeOver();
      }}
    >
      <main className="app-chat">
        <header className="chat-head">
          <span />
          <div className="chat-who">
            <Avatar sc={sc} size="sm" />
            <span className="chat-name">
              <b>{sc.name}</b>
            </span>
          </div>
          <span />
        </header>

        <motion.div ref={scroller} className="thread" layoutScroll>
          <div className="thread-in">
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
          </div>
        </motion.div>

        <Keyboard seed={seed} draftId={draftId} coach={coach} autotype={autotype} copied={copied} onSend={onSend} onSnapshot={setSnap} apiRef={kbApi} />
      </main>

      <motion.div
        className={cx("ghost lc-ghost", ghost.press && "press")}
        initial={false}
        animate={{ x: ghost.x, y: ghost.y, opacity: ghost.show ? 1 : 0 }}
        transition={{ x: { type: "spring", stiffness: 140, damping: 22 }, y: { type: "spring", stiffness: 140, damping: 22 }, opacity: { duration: 0.25 } }}
        style={{} as CSSProperties}
        aria-hidden
      >
        <span className="ghost-ring" />
        <Arrow />
      </motion.div>
    </div>
  );
}
