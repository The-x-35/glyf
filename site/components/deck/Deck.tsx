"use client";

import { motion } from "framer-motion";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { SCENARIOS, type Scenario } from "../chat/scenarios";
import ThemeToggle from "../ThemeToggle";
import BackdropKeys from "../BackdropKeys";
import { BoundKeysVisual, StickerField } from "../Features";
import LiveChat from "./LiveChat";
import { PAY_SCENARIO } from "./paymentScenario";

const ease = [0.22, 1, 0.36, 1] as const;
const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
const scenario = (id: string) => SCENARIOS.find((s) => s.id === id)!;

const Mark = ({ className }: { className?: string }) => (
  <span className={cx("wordmark", className)}>
    glyf<span className="dot" />
  </span>
);

const XMark = () => (
  <svg viewBox="0 0 24 24" width="1em" height="1em" fill="currentColor" aria-hidden>
    <path d="M18.24 2.25h3.31l-7.23 8.26 8.5 11.24h-6.65l-5.21-6.82-5.97 6.82H1.68l7.73-8.84L1.25 2.25h6.82l4.71 6.23zm-1.16 17.52h1.83L7.01 4.13H5.04z" />
  </svg>
);

type Slide = { id: string; label: string; tone?: "grey" | "ink"; render: (capture: boolean) => ReactNode };

/* ── building blocks ─────────────────────────────────────── */

function Demo({ id, use, eyebrow, points, capture }: { id?: string; use?: Scenario; eyebrow: string; points: string[]; capture: boolean }) {
  const sc = use ?? scenario(id!);
  return (
    <div className="d-demo">
      <div className="d-demo-copy">
        <p className="d-eyebrow">{eyebrow}</p>
        <h2 className="d-title">
          <span>{sc.headline[0]}</span> <span>{sc.headline[1]}</span>
        </h2>
        <ul className="d-points">
          {points.map((p) => (
            <li key={p}>{p}</li>
          ))}
        </ul>
      </div>
      <div className="d-demo-live">
        <LiveChat scenario={sc} capture={capture} />
      </div>
    </div>
  );
}

const Key = ({ k, dot, wide, label }: { k: string; dot?: boolean; wide?: boolean; label?: string }) => (
  <span className={cx("d-key", wide && "d-key--wide")}>
    {k}
    {dot && <i className="d-key-dot" />}
    {label && <small>{label}</small>}
  </span>
);

const TRIPS = [
  { task: "Share a café", steps: ["Open Maps", "Search", "Copy link", "Back to chat", "Paste"], apps: 2 },
  { task: "Send your address", steps: ["Open Notes", "Find it", "Copy", "Back to chat", "Paste"], apps: 2 },
  { task: "Sound professional", steps: ["Copy draft", "Open ChatGPT", "Prompt", "Copy", "Back", "Paste"], apps: 2 },
  { task: "Pay a friend in USDC", steps: ["Copy address", "Open wallet", "Paste", "Amount", "Confirm", "Back to chat"], apps: 2 },
  { task: "Book a meeting", steps: ["Open Calendar", "Find a slot", "Create event", "Copy invite", "Back to chat", "Paste"], apps: 2 },
];

const CONNECTORS = ["Google", "Notion", "Slack", "GitHub", "Linear", "Todoist", "Calendly", "Zoom", "Spotify"];
const TOOLS = [
  "Weather", "Crypto prices", "Currency", "Stocks", "Wikipedia", "Dictionary", "Synonyms", "Air quality", "Places", "Routes and ETA",
  "Holidays", "Books", "Tech news", "Sports", "Recipes", "Countries", "Food facts", "GitHub repos", "Quotes", "Jokes",
];

/* ── the slides ──────────────────────────────────────────── */

const SLIDES: Slide[] = [
  {
    id: "cover",
    label: "Glyf",
    render: () => (
      <div className="d-hero">
        <BackdropKeys />
        <div className="d-hero-copy">
          <h1 className="d-display">
            <span>Type less.</span>{" "}
            <span>
              <span className="hero-mark">
                glyf<span className="dot" />
              </span>{" "}
              more.
            </span>
          </h1>
          <p className="d-lede">The AI keyboard that does the rest.</p>
          <p className="d-foot">iPhone and Android · tryglyf.com</p>
        </div>
      </div>
    ),
  },
  {
    id: "problem",
    label: "Problem",
    render: () => (
      <div className="d-split">
        <div>
          <p className="d-eyebrow">The problem</p>
          <h2 className="d-title">
            <span>Your keyboard</span> <span>only types.</span>
          </h2>
          <p className="d-lede">Everything else is a trip out of the chat and back.</p>
        </div>
        <ol className="d-trips">
          {TRIPS.map((t) => (
            <li key={t.task}>
              <b>{t.task}</b>
              <span className="d-steps">
                {t.steps.map((s, i) => (
                  <span key={s} className="d-step">
                    {s}
                    {i < t.steps.length - 1 && <i>›</i>}
                  </span>
                ))}
              </span>
              <span className="d-count">{t.steps.length} steps</span>
            </li>
          ))}
        </ol>
      </div>
    ),
  },
  {
    id: "solution",
    label: "Solution",
    tone: "grey",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Glyf</p>
        <h2 className="d-title d-title--center">
          <span>It gets done</span> <span>where you type.</span>
        </h2>
        <div className="d-three">
          <div className="d-card">
            <div className="d-card-visual">
              <Key k="glyf" wide />
            </div>
            <b>Hold space</b>
            <p>AI works on what you typed: rewrites it, answers it, finds the place.</p>
          </div>
          <div className="d-card">
            <div className="d-card-visual">
              <Key k="V" dot />
              <Key k="C" dot />
            </div>
            <b>Hold a letter</b>
            <p>V shares your details and C opens the calendar. Every other letter is yours to bind.</p>
          </div>
          <div className="d-card">
            <div className="d-card-visual">
              <span className="d-chip">Show me places</span>
              <span className="d-chip">870</span>
            </div>
            <b>Tap the strip</b>
            <p>It reads what you are typing and offers the one move that finishes it.</p>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "apps",
    label: "All your apps",
    render: () => (
      <section className="features is-live d-apps" aria-label="One keyboard, all your apps">
        <StickerField>
          <h2 className="features-title">
            <span>One keyboard.</span> <span>All your apps.</span>
          </h2>
        </StickerField>
      </section>
    ),
  },
  {
    id: "rewrite",
    label: "AI rewrite",
    render: (c) => (
      <Demo
        id="neha"
        eyebrow="AI rewrite"
        capture={c}
        points={["Hold space on a messy draft", "Pick a tone: Polite, Shorter, Professional, Emoji", "The rewrite streams straight into the field"]}
      />
    ),
  },
  {
    id: "maps",
    label: "Maps",
    render: (c) => (
      <Demo
        id="sakshi"
        eyebrow="Search inside the keyboard"
        capture={c}
        points={["Google, YouTube and Maps without leaving the chat", "Results drop in as rich cards, not bare links", "Hold space on a sentence and Glyf picks the search"]}
      />
    ),
  },
  {
    id: "youtube",
    label: "YouTube + Google",
    render: (c) => (
      <Demo
        id="kabir"
        eyebrow="Answers and videos"
        capture={c}
        points={["Send the video itself, not a search screenshot", "Answers come back as cards: sunset at 6:24", "Live facts only from real providers, never made up"]}
      />
    ),
  },
  {
    id: "vault",
    label: "Vault",
    render: (c) => (
      <Demo
        id="mom"
        eyebrow="Knows you"
        capture={c}
        points={["Address, wallet address, socials: saved once", "Encrypted on the device, shared with the model only when you allow it", "Hold V, or tap the strip when a chat asks for it"]}
      />
    ),
  },
  {
    id: "math",
    label: "Math + stocks",
    render: (c) => (
      <Demo
        id="zoya"
        eyebrow="Smart strip"
        capture={c}
        points={["Type a sum, tap the answer", "Type a ticker, tap the price", "Two asks, two taps, zero app switches"]}
      />
    ),
  },
  {
    id: "pay",
    label: "Private payments",
    render: (c) => (
      <Demo
        use={PAY_SCENARIO}
        eyebrow="Payments"
        capture={c}
        points={[
          "Paste an address and the strip offers Pay",
          "Signed by your own wallet: Phantom. Glyf never holds a key",
          "Private transfers through MagicBlock, settled on Solana",
          "Token prices in the strip, in dollars",
        ]}
      />
    ),
  },
  {
    id: "skills",
    label: "Skills",
    render: () => (
      <div className="d-split">
        <div>
          <p className="d-eyebrow">Skills</p>
          <h2 className="d-title">
            <span>Bind anything</span> <span>to any key.</span>
          </h2>
          <ul className="d-points">
            <li>Describe a skill in plain English, get a runnable action</li>
            <li>Multiple steps, conditions and real tools</li>
            <li>It lands on a key, yours to keep. Sharing and a creator hub come later</li>
          </ul>
          <div className="features is-live d-bound">
            <BoundKeysVisual />
          </div>
        </div>
        <div className="d-builder">
          <div className="d-builder-ask">
            <small>Describe it</small>
            <p>When I hold M, tell them what is next on my calendar. If nothing is left today, say I am free.</p>
          </div>
          <ol className="d-builder-steps">
            <li>
              <span className="d-n">1</span>
              <code>calendar.today</code>
              <span>Read today&apos;s events</span>
            </li>
            <li>
              <span className="d-n">2</span>
              <code>if events</code>
              <span>Insert the next one</span>
            </li>
            <li className="d-else">
              <span className="d-n">↳</span>
              <code>else</code>
              <span>&ldquo;I&apos;m free, call anytime&rdquo;</span>
            </li>
          </ol>
          <div className="d-builder-bind">
            <span>Bound to</span>
            <Key k="M" dot />
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "connect",
    label: "Connectors",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Connectors and tools</p>
        <h2 className="d-title d-title--center">
          <span>Your apps,</span> <span>one key away.</span>
        </h2>
        <p className="d-lede d-lede--center">Nine apps sign in. Google and Notion run actions today.</p>
        <div className="d-cloud">
          {CONNECTORS.map((c) => (
            <span key={c} className="d-tag d-tag--strong">
              {c}
            </span>
          ))}
        </div>
        <div className="d-cloud d-cloud--soft">
          {TOOLS.map((c) => (
            <span key={c} className="d-tag">
              {c}
            </span>
          ))}
          <span className="d-tag">and more</span>
        </div>
        <p className="d-note">28 of the 30 built-in tools need no API key at all.</p>
        <div className="d-also">
          {["Dictation", "Clipboard history", "Emoji", "Notes", "Key themes", "Light and dark"].map((a) => (
            <span key={a}>{a}</span>
          ))}
        </div>
      </div>
    ),
  },
  {
    id: "trust",
    label: "Trust",
    render: () => (
      <div className="d-split">
        <div>
          <p className="d-eyebrow">Trust</p>
          <h2 className="d-title">
            <span>A keyboard sees everything.</span> <span>So we built it tight.</span>
          </h2>
        </div>
        <ul className="d-grid2">
          <li>
            <b>The keyboard never signs</b>
            <span>Payments hand off to your own wallet. Phantom signs, and no key ever touches Glyf</span>
          </li>
          <li>
            <b>Your details stay encrypted</b>
            <span>AES-GCM, in the Keychain and the Android Keystore. Sent to the model only when you allow it</span>
          </li>
          <li>
            <b>Silent in password fields</b>
            <span>No AI, no suggestions, no clipboard capture</span>
          </li>
          <li>
            <b>It learns how you type</b>
            <span>Your names, slang and shorthand stop getting corrected, and 20 vocabulary packs cover the rest</span>
          </li>
        </ul>
      </div>
    ),
  },
  {
    id: "market",
    label: "Why now",
    tone: "grey",
    render: () => (
      <div className="d-split">
        <div>
          <p className="d-eyebrow">Why now</p>
          <h2 className="d-title">
            <span>The keyboard is</span> <span>the next interface.</span>
          </h2>
          <p className="d-lede">It is the one app open inside every other app.</p>
        </div>
        <ul className="d-reasons">
          <li>
            <b>Models are fast enough</b>
            <span>Small models answer in well under a second, cheap enough to run on a keystroke</span>
          </li>
          <li>
            <b>The habit already exists</b>
            <span>People copy a message into a chatbot, fix it, and paste it back. The behaviour is set, the place is wrong</span>
          </li>
          <li>
            <b>Money moves like messages</b>
            <span>Stablecoins on Solana make paying a friend as quick as texting them</span>
          </li>
        </ul>
      </div>
    ),
  },
  {
    id: "model",
    label: "Business model",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Business model</p>
        <h2 className="d-title d-title--center">
          <span>Free to type.</span> <span>Pay to do more.</span>
        </h2>
        <div className="d-plans">
          <div>
            <small>Free</small>
            <b>$0</b>
            <span>10 AI actions a day</span>
          </div>
          <div>
            <small>Plus</small>
            <b>
              $2<em>/mo</em>
            </b>
            <span>100 AI actions a day</span>
          </div>
          <div className="is-max">
            <small>Max</small>
            <b>
              $5<em>/mo</em>
            </b>
            <span>500 AI actions a day</span>
          </div>
        </div>
        <p className="d-note">Later: fees on swaps and payments, and a creator marketplace for skills.</p>
      </div>
    ),
  },
  {
    id: "roadmap",
    label: "Roadmap",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Roadmap</p>
        <h2 className="d-title d-title--center">
          <span>What ships next.</span>
        </h2>
        <div className="d-road">
          <div>
            <small>Now</small>
            <ul>
              <li>Waitlist live at tryglyf.com</li>
              <li>Private beta on TestFlight</li>
            </ul>
          </div>
          <div>
            <small>Next</small>
            <ul>
              <li>Public TestFlight</li>
              <li>App Store and Google Play launch</li>
              <li>Plus and Max subscriptions</li>
            </ul>
          </div>
          <div>
            <small>Later</small>
            <ul>
              <li>Skills hub with creators</li>
            </ul>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "end",
    label: "Thank you",
    render: () => (
      <div className="d-cover d-end">
        <Mark className="d-end-mark" />
        <h2 className="d-end-line">Made for your thumbs.</h2>
        <p className="d-lede d-end-contact">
          tryglyf.com
          <span className="d-dot">·</span>
          <span className="d-x">
            <XMark />
            @Arpitx35
          </span>
        </p>
      </div>
    ),
  },
];

/* ── the deck ────────────────────────────────────────────── */

const fromHash = () => {
  if (typeof window === "undefined") return 0;
  const n = Number(window.location.hash.slice(1));
  return Number.isFinite(n) && n >= 1 && n <= SLIDES.length ? n - 1 : 0;
};

export default function Deck() {
  const [i, setI] = useState(0);
  const [dir, setDir] = useState(1);
  const [capture, setCapture] = useState(false);
  const [ready, setReady] = useState(false);
  const touch = useRef<{ x: number; y: number; demo: boolean } | null>(null);
  /** The slide we're on, readable from callbacks without making them stale. */
  const at = useRef(0);
  at.current = i;

  useEffect(() => {
    setI(fromHash());
    setCapture(new URLSearchParams(window.location.search).has("capture"));
    setReady(true);
    const onHash = () => setI(fromHash());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);

  // Plain state updates: an updater function can run during render, so the
  // direction and the URL are set here instead of inside one.
  const go = useCallback((n: number) => {
    const cur = at.current;
    const next = Math.max(0, Math.min(SLIDES.length - 1, n));
    if (next === cur) return;
    at.current = next;
    setDir(next > cur ? 1 : -1);
    setI(next);
    history.replaceState(null, "", `#${next + 1}`);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "ArrowRight" || e.key === "ArrowDown" || e.key === "PageDown") (e.preventDefault(), go(i + 1));
      else if (e.key === "ArrowLeft" || e.key === "ArrowUp" || e.key === "PageUp") (e.preventDefault(), go(i - 1));
      else if (e.key === "Home") go(0);
      else if (e.key === "End") go(SLIDES.length - 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [i, go]);

  const slide = SLIDES[i];

  return (
    <div
      className={cx("deck", capture && "is-capture")}
      onTouchStart={(e) => {
        const t = e.touches[0];
        touch.current = { x: t.clientX, y: t.clientY, demo: !!(e.target as HTMLElement).closest(".lc, .fx-stage") };
      }}
      onTouchEnd={(e) => {
        const s = touch.current;
        touch.current = null;
        if (!s || s.demo) return;
        const t = e.changedTouches[0];
        const dx = t.clientX - s.x;
        if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(t.clientY - s.y)) go(i + (dx < 0 ? 1 : -1));
      }}
    >
      {!capture && (
        <div className="deck-progress" aria-hidden>
          <motion.i animate={{ scaleX: (i + 1) / SLIDES.length }} transition={{ duration: 0.5, ease }} />
        </div>
      )}

      {/* The slide swaps instantly and only the entrance animates: an exit
          animation under mode="wait" wedged on fast clicks, leaving the old
          slide (or nothing) on stage until a refresh. */}
      {ready && (
        <motion.section
          key={slide.id}
          className={cx("slide", slide.tone && `slide--${slide.tone}`)}
          aria-label={`${i + 1} of ${SLIDES.length}: ${slide.label}`}
          initial={capture ? false : { opacity: 0, x: dir * 60 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4, ease }}
        >
          <div className="slide-in">{slide.render(capture)}</div>
        </motion.section>
      )}

      {!capture && (
        <nav className="deck-nav" aria-label="Slides">
          <a className="wordmark deck-home" href="/" aria-label="tryglyf.com">
            glyf<span className="dot" />
          </a>
          <span className="deck-label">{slide.label}</span>
          <div className="deck-ctl">
            <a
              className="deck-pdf"
              href="/glyf-pitch-deck.pdf"
              target="_blank"
              rel="noopener"
              onClick={(e) => {
                const root = document.documentElement;
                const dark = root.dataset.theme === "dark" || (!root.dataset.theme && matchMedia("(prefers-color-scheme: dark)").matches);
                if (dark) {
                  e.preventDefault();
                  window.open("/glyf-pitch-deck-dark.pdf", "_blank", "noopener");
                }
              }}
            >
              PDF
            </a>
            <ThemeToggle />
            <button type="button" onClick={() => go(i - 1)} disabled={i === 0} aria-label="Previous slide">
              ‹
            </button>
            <span className="deck-count">
              {String(i + 1).padStart(2, "0")} / {String(SLIDES.length).padStart(2, "0")}
            </span>
            <button type="button" onClick={() => go(i + 1)} disabled={i === SLIDES.length - 1} aria-label="Next slide">
              ›
            </button>
          </div>
        </nav>
      )}
    </div>
  );
}
