"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { SCENARIOS } from "../chat/scenarios";
import ThemeToggle from "../ThemeToggle";
import LiveChat from "./LiveChat";

const ease = [0.22, 1, 0.36, 1] as const;
const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
const scenario = (id: string) => SCENARIOS.find((s) => s.id === id)!;

const Mark = ({ className }: { className?: string }) => (
  <span className={cx("wordmark", className)}>
    glyf<span className="dot" />
  </span>
);

type Slide = { id: string; label: string; tone?: "grey" | "ink"; render: (capture: boolean) => ReactNode };

/* ── building blocks ─────────────────────────────────────── */

function Demo({ id, eyebrow, points, capture }: { id: string; eyebrow: string; points: string[]; capture: boolean }) {
  const sc = scenario(id);
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
      <div className="d-cover">
        <Mark className="d-cover-mark" />
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
              <Key k="W" dot />
            </div>
            <b>Hold a letter</b>
            <p>Fires the skill bound to it. Your address, a translation, the weather.</p>
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
    id: "rewrite",
    label: "AI rewrite",
    render: (c) => (
      <Demo
        id="neha"
        eyebrow="AI rewrite"
        capture={c}
        points={["Hold space on a messy draft", "Pick a tone: Polite, Shorter, Professional, Hinglish, Emoji", "The rewrite streams straight into the field"]}
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
        id="mumma"
        eyebrow="Knows you"
        capture={c}
        points={["Address, UPI, wallet, socials: saved once", "Encrypted on the device, never on our servers", "Hold V, or tap the strip when a chat asks for it"]}
      />
    ),
  },
  {
    id: "math",
    label: "Math + UPI",
    render: (c) => (
      <Demo
        id="zoya"
        eyebrow="Smart strip"
        capture={c}
        points={["Type a sum, tap the answer", "Talk about paying and your UPI is one tap away", "Two asks, two taps, zero app switches"]}
      />
    ),
  },
  {
    id: "autocorrect",
    label: "Autocorrect",
    render: (c) => (
      <Demo
        id="rohan"
        eyebrow="Typing engine"
        capture={c}
        points={["On-device autocorrect and prediction", "Understands Hinglish, learns your words", "20 vocabulary packs, no AI call needed"]}
      />
    ),
  },
  {
    id: "translate",
    label: "Translate",
    render: (c) => (
      <Demo
        id="sofia"
        eyebrow="Translate"
        capture={c}
        points={["Hold T and type in your own language", "The translation follows as you type", "Replace with one tap"]}
      />
    ),
  },
  {
    id: "pay",
    label: "Private payments",
    render: (c) => (
      <Demo
        id="semi"
        eyebrow="Payments"
        capture={c}
        points={[
          "Paste an address and the strip offers Pay",
          "Signed in the app with a Privy wallet. The keyboard never holds a key",
          "Private transfers through MagicBlock, settled on Solana",
        ]}
      />
    ),
  },
  {
    id: "skills",
    label: "Skills",
    tone: "grey",
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
            <li>Share on the Skills hub or install packs: Writer, Operator, Social, Desi</li>
          </ul>
        </div>
        <div className="d-builder">
          <div className="d-builder-ask">
            <small>Describe it</small>
            <p>When I hold M, find my next meeting and drop the Meet link. If there is none, say I am free.</p>
          </div>
          <ol className="d-builder-steps">
            <li>
              <span className="d-n">1</span>
              <code>calendar.today</code>
              <span>Find the next meeting</span>
            </li>
            <li>
              <span className="d-n">2</span>
              <code>if meet_link</code>
              <span>Insert the Meet link</span>
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
    tone: "ink",
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
            <span>Payments hand off to the app, where Privy holds the wallet. No key touches the keyboard</span>
          </li>
          <li>
            <b>Your details stay encrypted</b>
            <span>AES-GCM, in the Keychain and the Android Keystore. Sent to the model only when you allow it</span>
          </li>
          <li>
            <b>It refuses secrets</b>
            <span>Card numbers, seed phrases, API keys, OTPs and IDs are rejected, never stored</span>
          </li>
          <li>
            <b>Silent in password fields</b>
            <span>No AI, no suggestions, no clipboard capture</span>
          </li>
          <li>
            <b>Typing needs no network</b>
            <span>Autocorrect, prediction and 20 vocabulary packs run on the device</span>
          </li>
          <li>
            <b>No API keys in the app</b>
            <span>Model keys and OAuth tokens stay on the server</span>
          </li>
        </ul>
      </div>
    ),
  },
  {
    id: "built",
    label: "Where it stands",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Where it stands</p>
        <h2 className="d-title d-title--center">
          <span>It already runs</span> <span>on both phones.</span>
        </h2>
        <div className="d-stats">
          <div>
            <b>iOS</b>
            <span>App and keyboard on iPhone, on TestFlight</span>
          </div>
          <div>
            <b>Android</b>
            <span>Keyboard and app on device</span>
          </div>
          <div>
            <b>336</b>
            <span>Tests across the backend, iOS and Android</span>
          </div>
          <div>
            <b>30</b>
            <span>Tools and 9 connectors wired to the keys</span>
          </div>
        </div>
        <p className="d-note">Next: the backend on api.tryglyf.com, then the stores.</p>
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
            <b>The category is funded</b>
            <span>Acti raised a $5.3M seed led by BITKRAFT in June 2026 for an AI keyboard</span>
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
            <span>40 AI actions a day</span>
          </div>
          <div>
            <small>Plus</small>
            <b>
              $4.99<em>/mo</em>
            </b>
            <span>400 AI actions a day</span>
          </div>
          <div className="is-max">
            <small>Max</small>
            <b>
              $19.99<em>/mo</em>
            </b>
            <span>Unlimited</span>
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
              <li>Backend live at api.tryglyf.com</li>
              <li>Public TestFlight beta</li>
              <li>Waitlist to first users</li>
            </ul>
          </div>
          <div>
            <small>Next</small>
            <ul>
              <li>App Store and Google Play launch</li>
              <li>Plus and Max subscriptions</li>
              <li>Skills hub with creators</li>
            </ul>
          </div>
          <div>
            <small>Later</small>
            <ul>
              <li>Wallet release: private payments and swaps</li>
              <li>Per-contact memory and tone</li>
              <li>More languages</li>
            </ul>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "team",
    label: "Team",
    tone: "grey",
    render: () => (
      <div className="d-stack">
        <p className="d-eyebrow">Team</p>
        <div className="d-person">
          <span className="d-avatar">A</span>
          <div>
            <b>Arpit Singh</b>
            <span>Founder</span>
            <span className="d-contact">arpit@tryglyf.com</span>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "end",
    label: "Thank you",
    tone: "ink",
    render: () => (
      <div className="d-cover">
        <Mark className="d-cover-mark" />
        <h2 className="d-display">
          <span>Made for</span> <span>your thumbs.</span>
        </h2>
        <p className="d-lede">tryglyf.com · arpit@tryglyf.com</p>
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
        touch.current = { x: t.clientX, y: t.clientY, demo: !!(e.target as HTMLElement).closest(".lc") };
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

      {ready && (
        <AnimatePresence mode="wait" initial={false} custom={dir}>
          <motion.section
            key={slide.id}
            className={cx("slide", slide.tone && `slide--${slide.tone}`)}
            aria-label={`${i + 1} of ${SLIDES.length}: ${slide.label}`}
            custom={dir}
            initial={capture ? false : { opacity: 0, x: dir * 60 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: dir * -60 }}
            transition={{ duration: 0.45, ease }}
          >
            <div className="slide-in">{slide.render(capture)}</div>
          </motion.section>
        </AnimatePresence>
      )}

      {!capture && (
        <nav className="deck-nav" aria-label="Slides">
          <a className="wordmark deck-home" href="/" aria-label="tryglyf.com">
            glyf<span className="dot" />
          </a>
          <span className="deck-label">{slide.label}</span>
          <div className="deck-ctl">
            <a className="deck-pdf" href="/glyf-pitch-deck.pdf" target="_blank" rel="noopener">
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
