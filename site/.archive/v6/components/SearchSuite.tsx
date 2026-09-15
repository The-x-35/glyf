"use client";

import { AnimatePresence, motion, useInView } from "framer-motion";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * The search suite, demonstrated for real: chips switch Search / YouTube /
 * Maps, the query types itself, result cards stream in — and clicking a
 * card drops its link into the message with a "Copied" flash, exactly the
 * in-keyboard flow.
 */

type Tab = "web" | "yt" | "maps";

const QUERIES: Record<Tab, string> = {
  web: "what time does the sun set",
  yt: "lofi beats",
  maps: "coffee near me",
};

const INSERTS: Record<Tab, string[]> = {
  web: ["Sunset today is 6:13 PM 🌇", "goo.gl/sun-set"],
  yt: ["youtu.be/jfKfPfyJRdk", "youtu.be/n61ULEU7CO0"],
  maps: ["maps.app/blue-tokai", "maps.app/third-wave"],
};

export default function SearchSuite() {
  const [tab, setTab] = useState<Tab>("web");
  const [typed, setTyped] = useState("");
  const [showResults, setShowResults] = useState(false);
  const [message, setMessage] = useState("");
  const [copied, setCopied] = useState<number | null>(null);
  const [userDrove, setUserDrove] = useState(false);

  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { margin: "-120px", once: false });
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearTimers = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };

  const play = useCallback((t: Tab) => {
    clearTimers();
    setTab(t);
    setTyped("");
    setShowResults(false);
    setCopied(null);
    const q = QUERIES[t];
    for (let i = 1; i <= q.length; i++) {
      timers.current.push(setTimeout(() => setTyped(q.slice(0, i)), 260 + i * 34));
    }
    timers.current.push(
      setTimeout(() => setShowResults(true), 260 + q.length * 34 + 240),
    );
  }, []);

  // The demo always starts itself…
  useEffect(() => {
    const t = setTimeout(() => play("web"), 700);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // …and tours the tabs while on screen, until the visitor takes the wheel.
  useEffect(() => {
    if (!inView || userDrove) return;
    const order: Tab[] = ["web", "yt", "maps"];
    const next = order[(order.indexOf(tab) + 1) % order.length];
    const cycle = setTimeout(() => play(next), 5200);
    return () => clearTimeout(cycle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inView, tab, userDrove]);

  const drive = (t: Tab) => {
    setUserDrove(true);
    play(t);
  };

  const insert = (i: number) => {
    setUserDrove(true);
    setMessage(INSERTS[tab][i] ?? INSERTS[tab][0]);
    setCopied(i);
    timers.current.push(setTimeout(() => setCopied(null), 1400));
  };

  const chip = (t: Tab, label: string, icon: React.ReactNode) => (
    <button
      key={t}
      type="button"
      className={`ss-chip ${tab === t ? "active" : ""}`}
      onClick={() => drive(t)}
    >
      {icon}
      {label}
    </button>
  );

  return (
    <div className="ss" ref={ref}>
      <div className="ss-screen">
        <div className="ss-msg-label">
          Message
          <AnimatePresence>
            {copied !== null && (
              <motion.span
                className="ss-copied"
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
              >
                ✓ Copied
              </motion.span>
            )}
          </AnimatePresence>
        </div>
        <div className="ss-msg">
          {message || <span className="ss-msg-ghost">Tap a result…</span>}
          <span className="caret" />
        </div>
      </div>

      <div className="ss-panel">
        <div className="ss-chips">
          {chip("web", "Search", <GIcon />)}
          {chip("yt", "YouTube", <YtIcon />)}
          {chip("maps", "Maps", <PinIcon />)}
          <span className="ss-contacts">Contacts</span>
        </div>

        <div className="ss-query">
          <SearchGlyph />
          <span>{typed}</span>
          <span className="caret" />
        </div>

        <div className="ss-results">
          <AnimatePresence mode="wait">
            {showResults && (
              <motion.div
                key={tab}
                className="ss-cards"
                initial="hide"
                animate="show"
                exit={{ opacity: 0, y: -6, transition: { duration: 0.16 } }}
                variants={{
                  show: { transition: { staggerChildren: 0.09 } },
                  hide: {},
                }}
              >
                {tab === "web" && <WebResults onPick={insert} copied={copied} />}
                {tab === "yt" && <YtResults onPick={insert} copied={copied} />}
                {tab === "maps" && <MapResults onPick={insert} copied={copied} />}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

const cardVariants = {
  hide: { opacity: 0, y: 16, scale: 0.98 },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: { type: "spring" as const, stiffness: 420, damping: 32 },
  },
};

function WebResults({
  onPick,
  copied,
}: {
  onPick: (i: number) => void;
  copied: number | null;
}) {
  return (
    <>
      <motion.button
        type="button"
        className="ss-card ss-sun"
        variants={cardVariants}
        whileHover={{ y: -3 }}
        whileTap={{ scale: 0.98 }}
        onClick={() => onPick(0)}
      >
        <div className="ss-sun-time">6:13 PM</div>
        <div className="ss-sun-sub">Sunset · today</div>
        <div className="ss-sun-arc">
          <svg viewBox="0 0 120 44" aria-hidden>
            <path
              d="M4 40 Q60 -14 116 40"
              fill="none"
              stroke="rgba(255,255,255,0.55)"
              strokeWidth="2"
              strokeDasharray="3 5"
            />
            <circle cx="86" cy="12.5" r="6" fill="#FFD36E" />
          </svg>
        </div>
        {copied === 0 && <span className="ss-card-copied">Inserted</span>}
      </motion.button>
      <motion.button
        type="button"
        className="ss-card ss-row"
        variants={cardVariants}
        whileHover={{ y: -3 }}
        whileTap={{ scale: 0.98 }}
        onClick={() => onPick(1)}
      >
        <span className="ss-row-icon"><SearchGlyph /></span>
        <span className="ss-row-lines">
          <b>Golden hour begins 5:41 PM</b>
          <i>timeanddate.com</i>
        </span>
        {copied === 1 && <span className="ss-card-copied">Inserted</span>}
      </motion.button>
    </>
  );
}

function YtResults({
  onPick,
  copied,
}: {
  onPick: (i: number) => void;
  copied: number | null;
}) {
  const vids = [
    {
      t: "lofi hip hop radio — beats to relax/study to",
      c: "Lofi Girl",
      d: "LIVE",
      cls: "thumb-a",
    },
    {
      t: "Midnight Drive — synthwave mix",
      c: "Nightride FM",
      d: "1:02:14",
      cls: "thumb-b",
    },
  ];
  return (
    <>
      {vids.map((v, i) => (
        <motion.button
          key={v.t}
          type="button"
          className="ss-card ss-video"
          variants={cardVariants}
          whileHover={{ y: -3 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => onPick(i)}
        >
          <span className={`ss-thumb ${v.cls}`}>
            <svg viewBox="0 0 24 24" width="26" height="26" aria-hidden>
              <circle cx="12" cy="12" r="11" fill="rgba(255,255,255,0.9)" />
              <path d="M10 8.2v7.6l6-3.8z" fill="#17181c" />
            </svg>
            <em>{v.d}</em>
          </span>
          <span className="ss-row-lines">
            <b>{v.t}</b>
            <i>{v.c}</i>
          </span>
          {copied === i && <span className="ss-card-copied">Inserted</span>}
        </motion.button>
      ))}
    </>
  );
}

function MapResults({
  onPick,
  copied,
}: {
  onPick: (i: number) => void;
  copied: number | null;
}) {
  return (
    <>
      <motion.button
        type="button"
        className="ss-card ss-map"
        variants={cardVariants}
        whileHover={{ y: -3 }}
        whileTap={{ scale: 0.98 }}
        onClick={() => onPick(0)}
      >
        <span className="ss-map-art" aria-hidden>
          <svg viewBox="0 0 130 84">
            <rect width="130" height="84" rx="10" fill="#E8F0E9" />
            <path d="M-6 58 C30 48 44 70 74 60 S 120 40 140 46" stroke="#fff" strokeWidth="7" fill="none" />
            <path d="M28 -6 C 22 30 44 40 40 90" stroke="#fff" strokeWidth="5" fill="none" />
            <path d="M90 -8 L 84 92" stroke="#D8E4DA" strokeWidth="4" />
            <rect x="12" y="14" width="18" height="12" rx="2" fill="#D3DFD5" />
            <rect x="104" y="58" width="16" height="14" rx="2" fill="#D3DFD5" />
          </svg>
          <motion.span
            className="ss-pin"
            initial={{ y: -18, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ type: "spring", stiffness: 460, damping: 20, delay: 0.28 }}
          >
            <PinIcon big />
          </motion.span>
        </span>
        <span className="ss-row-lines">
          <b>Blue Tokai Coffee</b>
          <i>350 m · Open till 11 PM</i>
        </span>
        {copied === 0 && <span className="ss-card-copied">Inserted</span>}
      </motion.button>
      <motion.button
        type="button"
        className="ss-card ss-row"
        variants={cardVariants}
        whileHover={{ y: -3 }}
        whileTap={{ scale: 0.98 }}
        onClick={() => onPick(1)}
      >
        <span className="ss-row-icon"><PinIcon /></span>
        <span className="ss-row-lines">
          <b>Third Wave Coffee</b>
          <i>600 m · 4.6 ★</i>
        </span>
        {copied === 1 && <span className="ss-card-copied">Inserted</span>}
      </motion.button>
    </>
  );
}

/* tiny inline icons */

function SearchGlyph() {
  return (
    <svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <circle cx="8.6" cy="8.6" r="5.6" />
      <path d="M13 13 L17.5 17.5" />
    </svg>
  );
}

function GIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden>
      <path fill="#4285F4" d="M23 12.3c0-.8-.1-1.6-.2-2.3H12v4.5h6.2a5.3 5.3 0 0 1-2.3 3.5v2.9h3.7c2.2-2 3.4-5 3.4-8.6z" />
      <path fill="#34A853" d="M12 23c3.1 0 5.7-1 7.6-2.8l-3.7-2.9c-1 .7-2.4 1.1-3.9 1.1-3 0-5.5-2-6.4-4.7H1.8v3A11.5 11.5 0 0 0 12 23z" />
      <path fill="#FBBC05" d="M5.6 13.7a6.9 6.9 0 0 1 0-4.4v-3H1.8a11.5 11.5 0 0 0 0 10.4z" />
      <path fill="#EA4335" d="M12 4.6c1.7 0 3.2.6 4.4 1.7L19.6 3A11.5 11.5 0 0 0 1.8 6.3l3.8 3C6.5 6.6 9 4.6 12 4.6z" />
    </svg>
  );
}

function YtIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden>
      <rect x="1.5" y="4.5" width="21" height="15" rx="4.4" fill="#FF0033" />
      <path d="M10 9v6l5.4-3z" fill="#fff" />
    </svg>
  );
}

function PinIcon({ big = false }: { big?: boolean }) {
  const s = big ? 26 : 14;
  return (
    <svg width={s} height={s} viewBox="0 0 24 24" aria-hidden>
      <path
        d="M12 2a7.4 7.4 0 0 0-7.4 7.4C4.6 14.9 12 22 12 22s7.4-7.1 7.4-12.6A7.4 7.4 0 0 0 12 2z"
        fill={big ? "#EA4335" : "currentColor"}
      />
      <circle cx="12" cy="9.4" r="2.7" fill="#fff" />
    </svg>
  );
}
