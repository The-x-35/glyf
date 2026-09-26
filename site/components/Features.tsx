"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import { MagicBlockMark } from "./kb/brands";
import {
  ArrowDownIcon,
  CalendarCheckIcon,
  CalendarIcon,
  GifIcon,
  LinkIcon,
  LockIcon,
  PersonIcon,
  PinIcon,
  PlayRectIcon,
  SearchIcon,
  SparkIcon,
  SwapIcon,
  TranslateIcon,
  VideoIcon,
  WalletIcon,
} from "./kb/icons";

/** What Glyf does and what it works with, ahead of the chats that show it.
 *  The apps float around the headline like stickers on a desk: pick any up
 *  and put it somewhere else. The cards play the keyboard's own moves on a
 *  loop while they are on screen. */

type Vars = CSSProperties & Record<`--${string}`, string | number>;

/* ── The field around the headline ───────────────────────────────────────
   Positions are % of the stage (x from the left or right from the right,
   y from the top); mx, mright and my place it on phones, where only the
   ones with m show. d is depth (how far it follows the pointer and drifts
   with the scroll); t and delay pace its bob. */
type Float = {
  x?: string;
  right?: string;
  y: string;
  m?: { x?: string; right?: string; y: string };
  /** Only where there is room for it (wider than a small laptop). */
  wide?: boolean;
  r: number;
  d: number;
  t: number;
  delay: number;
  el: ReactNode;
};

const Tile = ({ bg, children, label }: { bg: string; children: ReactNode; label: string }) => (
  <span className="fx-tile" style={{ background: bg }} title={label}>
    {children}
  </span>
);

const FLOATS: Float[] = [
  { x: "3%", y: "8%", m: { x: "2%", y: "4%" }, r: -10, d: 0.9, t: 6.2, delay: 0,
    el: <Tile bg="linear-gradient(160deg, #4b8df8, #1a62d6)" label="Google Calendar"><CalendarIcon /></Tile> },
  { x: "20%", y: "3%", wide: true, r: 4, d: 0.45, t: 7.4, delay: -2.1,
    el: <span className="fx-bubble">let&apos;s get coffee ☕</span> },
  { x: "46%", y: "0%", m: { x: "42%", y: "1%" }, r: 0, d: 1, t: 5.6, delay: -1.2,
    // eslint-disable-next-line @next/next/no-img-element
    el: <img className="fx-coin" src="/brands/sol.png" alt="" width={58} height={58} /> },
  { right: "22%", y: "6%", r: 8, d: 0.6, t: 6.8, delay: -3.4,
    el: <Tile bg="linear-gradient(160deg, #3fcf6d, #1e9e4a)" label="Google Maps"><PinIcon /></Tile> },
  { right: "3%", y: "12%", r: -6, d: 0.8, t: 7.9, delay: -0.6,
    el: <Tile bg="linear-gradient(160deg, #26262b, #0b0b0e)" label="MagicBlock"><MagicBlockMark /></Tile> },
  { x: "8%", y: "44%", r: -7, d: 1.1, t: 5.2, delay: -2.6,
    el: <span className="fx-key">C<span className="fx-keydot" /></span> },
  { right: "4%", y: "30%", m: { x: "22%", y: "22%" }, r: 6, d: 1.05, t: 6.4, delay: -1.8,
    el: <span className="fx-gkey">g<span className="fx-gdot" /></span> },
  { x: "1%", y: "74%", m: { x: "2%", y: "72%" }, r: 7, d: 0.7, t: 7.1, delay: -4.2,
    el: <Tile bg="linear-gradient(160deg, #1fb57a, #0b8a58)" label="Google Meet"><VideoIcon /></Tile> },
  { x: "10%", y: "86%", wide: true, r: -3, d: 0.5, t: 8.2, delay: -1.5,
    el: (
      <span className="fx-chip">
        <CalendarIcon /> <b>Demo call</b> <span>6:00 PM</span>
      </span>
    ) },
  { x: "43%", y: "80%", m: { x: "44%", y: "86%" }, r: 5, d: 0.95, t: 5.9, delay: -3.1,
    el: <span className="fx-key">T<span className="fx-keydot" /></span> },
  { right: "30%", y: "80%", wide: true, r: -4, d: 0.55, t: 7.6, delay: -0.3,
    el: (
      <span className="fx-chip">
        <span className="fx-cash">$</span> <b>1 AAPL</b> <span>$341.07</span>
      </span>
    ) },
  { right: "12%", y: "78%", m: { right: "4%", y: "70%" }, r: -9, d: 0.85, t: 6.6, delay: -2.4,
    el: <Tile bg="linear-gradient(160deg, #ff4d5e, #e0102a)" label="YouTube"><PlayRectIcon /></Tile> },
  { right: "1%", y: "62%", wide: true, r: 10, d: 0.65, t: 7.2, delay: -5,
    // eslint-disable-next-line @next/next/no-img-element
    el: <img className="fx-coin fx-coin-sm" src="/brands/usdc.png" alt="" width={46} height={46} /> },
  { x: "27%", y: "16%", r: -5, d: 0.3, t: 8.6, delay: -3.8,
    el: <Tile bg="linear-gradient(160deg, #ff5fb3, #d81b7c)" label="GIFs by KLIPY"><GifIcon /></Tile> },
  { right: "28%", y: "18%", wide: true, r: 6, d: 0.35, t: 8, delay: -1,
    el: <Tile bg="linear-gradient(160deg, #19c2e6, #9be15d)" label="Jupiter"><SwapIcon /></Tile> },
  { x: "28%", y: "70%", r: -6, d: 0.4, t: 9, delay: -2.8,
    el: <span className="fx-note fx-note-yellow">coffee at 6? ☕</span> },
  { right: "33%", y: "0%", m: { right: "2%", y: "2%" }, r: 5, d: 0.5, t: 8.4, delay: -4.4,
    el: <span className="fx-note fx-note-pink">send me the Meet link!</span> },
];

/** Where a sticker starts: its place as CSS variables, so a phone can move
 *  it (globals.css) and a drag, writing left and top, can override both. */
const place = (f: Float): Vars => ({
  "--x": f.x ?? "auto",
  "--rt": f.right ?? "auto",
  "--y": f.y,
  ...(f.m ? { "--mx": f.m.x ?? "auto", "--mrt": f.m.right ?? "auto", "--my": f.m.y } : {}),
});

/* ── Cards ─────────────────────────────────────────────────────────────── */

/** Hold a key, it runs its action: the app's default bindings. */
const BOUND = [
  { key: "C", label: "Calendar", icon: <CalendarIcon />, result: "Demo call · 6:00 PM" },
  { key: "V", label: "Vault", icon: <LockIcon />, result: "123, A-block, Delhi" },
  { key: "T", label: "Translate", icon: <TranslateIcon />, result: "hasta mañana" },
  { key: "M", label: "Meet link", icon: <VideoIcon />, result: "meet.google.com/abc-defg" },
];

/** The strip's tools and what each opens above the keys. */
const TOOLS = [
  { icon: <SearchIcon />, label: "Search", panel: "coffee near me" },
  { icon: <PinIcon />, label: "Maps", panel: "Bean & Byte Café · 350 m" },
  { icon: <CalendarIcon />, label: "Calendar", panel: "Demo call · Tomorrow 6:00 PM" },
  { icon: <WalletIcon />, label: "Wallet", panel: "Send 200 USDC, privately" },
  { icon: <TranslateIcon />, label: "Translate", panel: "see you tomorrow → hasta mañana" },
  { icon: <SparkIcon />, label: "AI", panel: "Tidy this up" },
];

/** Answers that land in the strip instead of in another app. */
const ANSWERS = [
  { icon: <PinIcon />, text: "Bean & Byte Café", meta: "350 m" },
  { icon: <CalendarIcon />, text: "Demo call", meta: "Tomorrow 6:00 PM" },
  { icon: <span className="feat-cash">$</span>, text: "1 AAPL", meta: "$341.07" },
];

/** What the keyboard reaches today (Connected tools, the wallet, search). */
const WORKS_WITH = [
  { icon: <CalendarIcon />, name: "Google Calendar" },
  { icon: <VideoIcon />, name: "Google Meet" },
  { icon: <CalendarCheckIcon />, name: "Cal.com" },
  { icon: <LinkIcon />, name: "Calendly" },
  { icon: <MagicBlockMark />, name: "MagicBlock" },
  { icon: <WalletIcon />, name: "Solana wallet" },
  { icon: <SwapIcon />, name: "Jupiter" },
  { icon: <PinIcon />, name: "Google Maps" },
  { icon: <PlayRectIcon />, name: "YouTube" },
  { icon: <PersonIcon />, name: "Contacts" },
  { icon: <GifIcon />, name: "GIFs by KLIPY" },
];

type Drag = { el: HTMLElement; id: number; sx: number; sy: number; ox: number; oy: number };

export default function Features() {
  const section = useRef<HTMLElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const top = useRef(10);

  // The loops only run while the section is on screen.
  useEffect(() => {
    const el = section.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => el.classList.toggle("is-live", e.isIntersecting), {
      rootMargin: "80px 0px",
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  // The field leans toward the pointer, the nearer things more (held still
  // while something is being carried, so it stays under the pointer).
  const lean = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = stage.current;
    if (!el || e.pointerType === "touch" || drag.current) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty("--px", (((e.clientX - r.left) / r.width) * 2 - 1).toFixed(3));
    el.style.setProperty("--py", (((e.clientY - r.top) / r.height) * 2 - 1).toFixed(3));
  };
  const settle = () => {
    stage.current?.style.setProperty("--px", "0");
    stage.current?.style.setProperty("--py", "0");
  };

  // Pick a sticker up, carry it, put it down anywhere on the stage. It
  // stays where it lands, on top of the others.
  const grab = (e: React.PointerEvent<HTMLSpanElement>) => {
    if (e.button !== 0) return;
    const el = e.currentTarget;
    const left = el.offsetLeft;
    const top_ = el.offsetTop;
    el.style.left = `${left}px`;
    el.style.top = `${top_}px`;
    el.style.right = "auto";
    el.style.zIndex = String(++top.current);
    el.setPointerCapture(e.pointerId);
    el.classList.add("is-dragging");
    drag.current = { el, id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: left, oy: top_ };
    e.preventDefault();
  };
  const carry = (e: React.PointerEvent<HTMLSpanElement>) => {
    const d = drag.current;
    if (!d || d.id !== e.pointerId) return;
    const field = d.el.offsetParent as HTMLElement | null;
    const w = d.el.offsetWidth;
    const h = d.el.offsetHeight;
    const maxX = (field?.clientWidth ?? 0) - w / 3;
    const maxY = (field?.clientHeight ?? 0) - h / 3;
    const x = Math.min(maxX, Math.max(-w * 0.66, d.ox + e.clientX - d.sx));
    const y = Math.min(maxY, Math.max(-h * 0.66, d.oy + e.clientY - d.sy));
    d.el.style.left = `${x}px`;
    d.el.style.top = `${y}px`;
  };
  const drop = (e: React.PointerEvent<HTMLSpanElement>) => {
    const d = drag.current;
    if (!d || d.id !== e.pointerId) return;
    if (d.el.hasPointerCapture(d.id)) d.el.releasePointerCapture(d.id);
    d.el.classList.remove("is-dragging");
    drag.current = null;
  };

  // A soft light follows the pointer across a card.
  const spot = (e: React.PointerEvent<HTMLElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    e.currentTarget.style.setProperty("--mx", `${e.clientX - r.left}px`);
    e.currentTarget.style.setProperty("--my", `${e.clientY - r.top}px`);
  };

  return (
    <section className="features" id="features" aria-labelledby="features-title" ref={section}>
      <div className="wrap">
        <div className="fx-stage" ref={stage} onPointerMove={lean} onPointerLeave={settle}>
          <div className="fx-field" aria-hidden>
            {FLOATS.map((f, i) => (
              <span
                key={i}
                className={`fx${f.m ? "" : " fx-desk"}${f.wide ? " fx-wide" : ""}`}
                style={place(f)}
                onPointerDown={grab}
                onPointerMove={carry}
                onPointerUp={drop}
                onPointerCancel={drop}
              >
                <span className="fx-par" style={{ "--d": f.d } as Vars}>
                  <span
                    className="fx-float"
                    style={{ "--r": `${f.r}deg`, "--t": `${f.t}s`, "--delay": `${f.delay}s` } as Vars}
                  >
                    {f.el}
                  </span>
                </span>
              </span>
            ))}
          </div>
          <h2 className="features-title" id="features-title">
            <span>One keyboard.</span> <span>All your apps.</span>
          </h2>
        </div>

        <div className="feat-grid">
          <article className="feat" onPointerMove={spot}>
            <div className="feat-visual" aria-hidden>
              <div className="feat-results">
                {BOUND.map((b, i) => (
                  <span className="feat-result" key={b.key} style={{ "--i": i } as Vars}>
                    {b.icon}
                    {b.result}
                  </span>
                ))}
              </div>
              <div className="feat-keys">
                {BOUND.map((b, i) => (
                  <span className="feat-bound" key={b.key} style={{ "--i": i } as Vars}>
                    <span className="feat-key">
                      {b.key}
                      <span className="feat-keydot" />
                      <span className="feat-ring" />
                    </span>
                    <small>{b.label}</small>
                  </span>
                ))}
              </div>
            </div>
            <h3>Bind any action to any key.</h3>
          </article>

          <article className="feat" onPointerMove={spot}>
            <div className="feat-visual" aria-hidden>
              <div className="feat-panel">
                {TOOLS.map((t, i) => (
                  <span className="feat-panel-item" key={t.label} style={{ "--i": i } as Vars}>
                    {t.icon}
                    {t.panel}
                  </span>
                ))}
              </div>
              <div className="feat-strip">
                <span className="feat-g">
                  g<span className="feat-gdot" />
                </span>
                <span className="feat-tools">
                  <span className="feat-hl" />
                  {TOOLS.map((t, i) => (
                    <span className="feat-tool" key={t.label} style={{ "--i": i } as Vars}>
                      {t.icon}
                    </span>
                  ))}
                </span>
              </div>
            </div>
            <h3>AI and all your apps, inside the keyboard.</h3>
          </article>

          <article className="feat" onPointerMove={spot}>
            <div className="feat-visual" aria-hidden>
              <div className="feat-answers">
                {ANSWERS.map((a, i) => (
                  <span className="feat-answer" key={a.text} style={{ "--i": i } as Vars}>
                    <span className="feat-answer-icon">{a.icon}</span>
                    <b>{a.text}</b>
                    <span>{a.meta}</span>
                  </span>
                ))}
              </div>
            </div>
            <h3>Skip the trips between apps.</h3>
          </article>
        </div>

        <div className="works">
          <h3 className="works-title">Works with</h3>
          <ul className="works-list">
            {WORKS_WITH.map((w, i) => (
              <li key={w.name} style={{ "--i": i } as Vars}>
                <span className="works-icon" aria-hidden>
                  {w.icon}
                </span>
                {w.name}
              </li>
            ))}
          </ul>
        </div>

        <div className="try-cue">
          <p>Try it here.</p>
          <a className="try-arrow" href="#try" aria-label="Go to the chats">
            <ArrowDownIcon />
          </a>
        </div>
      </div>
    </section>
  );
}
