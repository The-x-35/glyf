"use client";

import { AnimatePresence, motion } from "framer-motion";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";

/**
 * The hero demo: a live Glyf keyboard. Type on your real keyboard (or tap
 * the keys) and the screen above fills in. HOLD a bound key — P, T or U —
 * and the glyf fires: charge ring, then the text transforms in place,
 * streamed like the real engine. Theme pills reskin it live.
 */

const ROW1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"];
const ROW2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"];
const ROW3 = ["z", "x", "c", "v", "b", "n", "m"];

const BOUND: Record<string, { name: string; run: (s: string) => string }> = {
  p: {
    name: "Proofread",
    run: (s) =>
      s
        .replace(/\bteh\b/gi, "the")
        .replace(/\bi\b/g, "I")
        .replace(/\bdont\b/gi, "don't")
        .replace(/\bim\b/gi, "I'm")
        .replace(/\brecieve\b/gi, "receive")
        .replace(/\bwont\b/gi, "won't")
        .replace(/\s+/g, " ")
        .trim()
        .replace(/^(\w)/, (m) => m.toUpperCase())
        .replace(/([^.!?])$/, "$1."),
  },
  t: {
    name: "Translate · Spanish",
    run: () => "Oye — llego cinco minutos tarde, pide por mí. ☕",
  },
  u: {
    name: "Summarize",
    run: () => "Running 5 late — order for me.",
  },
};

const SEED = "hey im running 5 mins late dont order without me";

const THEMES = [
  { id: "glass", label: "Glass", swatch: "#d3d6db" },
  { id: "dusk", label: "Dusk", swatch: "linear-gradient(135deg,#7C5CFF,#EC6ADE)" },
  { id: "ocean", label: "Ocean", swatch: "linear-gradient(135deg,#3D8BFF,#41E0C8)" },
  { id: "ember", label: "Ember", swatch: "linear-gradient(135deg,#FF7847,#FFC53D)" },
  { id: "ink", label: "Ink", swatch: "#17181C" },
];

const HOLD_MS = 420;

type Surface = null | "bar" | "clip" | "vault" | "emoji";

const CLIPS = [
  "the figma link from standup",
  "flight PNR · QR7GH2",
  "arpit@tryglyf.com",
];

const VAULT = [
  { label: "Home", value: "Flat 4B, Indiranagar, Bengaluru" },
  { label: "UPI", value: "arpit@okbank" },
  { label: ";sig", value: "— Arpit · arpit@tryglyf.com" },
];

const EMOJI = ["😂", "❤️", "🔥", "🙏", "🎉", "😭", "💀", "✨"];

/** The g bar's pocket engine — instruction keywords → canned rewrites. */
function barRun(prompt: string): string {
  const p = prompt.toLowerCase();
  if (/formal|professional|polite/.test(p))
    return "Hi — I'm running about five minutes late; please go ahead and order for me.";
  if (/short|tight|brief/.test(p)) return "Running 5 late — order for me.";
  if (/emoji/.test(p)) return "hey 🏃💨 5 mins late ⏰ don't order without me 🙏";
  if (/spanish|translate/.test(p)) return "Oye — llego cinco minutos tarde, pide por mí.";
  if (/rhyme|poem/.test(p))
    return "I'm five behind, don't hold the date — just save my seat and hold my plate.";
  if (/hindi/.test(p)) return "अरे — पाँच मिनट लेट हूँ, मेरे लिए order कर देना।";
  return "Hey! Running five minutes late — please order for me, I'll be right there.";
}

export default function GlyfKeyboard() {
  const [text, setText] = useState(SEED);
  const [theme, setTheme] = useState("glass");
  const [pressed, setPressed] = useState<Set<string>>(new Set());
  const [charging, setCharging] = useState<string | null>(null);
  const [fired, setFired] = useState<string | null>(null);
  const [running, setRunning] = useState<string | null>(null);
  const [surface, setSurface] = useState<Surface>(null);
  const [barPrompt, setBarPrompt] = useState("");
  const [barResult, setBarResult] = useState<string | null>(null);
  const surfaceRef = useRef<Surface>(null);
  surfaceRef.current = surface;

  const holdTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const holdFired = useRef(false);
  const streamTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const textRef = useRef(text);
  textRef.current = text;

  const setKeyPressed = (k: string, on: boolean) =>
    setPressed((prev) => {
      const next = new Set(prev);
      if (on) next.add(k);
      else next.delete(k);
      return next;
    });

  const runGlyf = useCallback((key: string) => {
    const glyf = BOUND[key];
    if (!glyf) return;
    holdFired.current = true;
    setCharging(null);
    setFired(key);
    setRunning(glyf.name);
    setTimeout(() => setFired(null), 380);

    const result = glyf.run(textRef.current || SEED);
    if (streamTimer.current) clearInterval(streamTimer.current);
    setText("");
    let i = 0;
    streamTimer.current = setInterval(() => {
      i += 1 + Math.floor(Math.random() * 2);
      setText(result.slice(0, i));
      if (i >= result.length) {
        if (streamTimer.current) clearInterval(streamTimer.current);
        streamTimer.current = null;
        setText(result);
        setRunning(null);
      }
    }, 26);
  }, []);

  const keyDown = useCallback(
    (k: string) => {
      setKeyPressed(k, true);
      holdFired.current = false;
      if (BOUND[k]) {
        setCharging(k);
        if (holdTimer.current) clearTimeout(holdTimer.current);
        holdTimer.current = setTimeout(() => runGlyf(k), HOLD_MS);
      }
    },
    [runGlyf],
  );

  const keyUp = useCallback((k: string) => {
    setKeyPressed(k, false);
    setCharging(null);
    if (holdTimer.current) {
      clearTimeout(holdTimer.current);
      holdTimer.current = null;
    }
    if (holdFired.current) return; // the hold consumed this press
    // With the g bar open, keys type the INSTRUCTION (app behavior).
    if (k === "return" && surfaceRef.current === "bar") {
      runBarRef.current?.();
      return;
    }
    const editor = surfaceRef.current === "bar" ? setBarPrompt : setText;
    if (k === "backspace") {
      editor((t) => t.slice(0, -1));
    } else if (k === "space") {
      editor((t) => (t.length > 260 ? t : t + " "));
    } else if (k.length === 1) {
      editor((t) => (t.length > 260 ? t : t + k));
    }
  }, []);

  const openSurface = (s: Surface) => {
    setSurface((cur) => (cur === s ? null : s));
    setBarResult(null);
    if (s !== "bar") setBarPrompt("");
  };

  const runBarRef = useRef<(() => void) | null>(null);
  const runBar = useCallback(() => {
    const result = barRun(barPrompt || "polish it");
    setBarResult("");
    let i = 0;
    if (streamTimer.current) clearInterval(streamTimer.current);
    streamTimer.current = setInterval(() => {
      i += 1 + Math.floor(Math.random() * 2);
      setBarResult(result.slice(0, i));
      if (i >= result.length) {
        if (streamTimer.current) clearInterval(streamTimer.current);
        streamTimer.current = null;
        setBarResult(result);
      }
    }, 22);
  }, [barPrompt]);

  runBarRef.current = runBar;

  const insertFromSurface = (v: string) => {
    setText((t) => (t ? t + " " + v : v));
  };

  // Physical keyboard wiring — the site keyboard mirrors your hands.
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA")) return;
      const k = e.key.toLowerCase();
      if (k === "backspace") {
        e.preventDefault();
        if (!pressed.has("backspace")) keyDown("backspace");
        return;
      }
      if (k === " " || e.code === "Space") {
        e.preventDefault();
        if (!pressed.has("space")) keyDown("space");
        return;
      }
      if (k === "enter" && surfaceRef.current === "bar") {
        e.preventDefault();
        runBarRef.current?.();
        return;
      }
      if (k === "escape" && surfaceRef.current) {
        setSurface(null);
        return;
      }
      if (/^[a-z]$/.test(k) && !e.metaKey && !e.ctrlKey && !e.altKey) {
        e.preventDefault();
        if (!e.repeat) keyDown(k);
      }
    };
    const up = (e: KeyboardEvent) => {
      const k = e.key.toLowerCase();
      if (k === "backspace") keyUp("backspace");
      else if (k === " " || e.code === "Space") keyUp("space");
      else if (/^[a-z]$/.test(k)) keyUp(k);
    };
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    return () => {
      window.removeEventListener("keydown", down);
      window.removeEventListener("keyup", up);
    };
  }, [keyDown, keyUp, pressed]);

  useEffect(
    () => () => {
      if (holdTimer.current) clearTimeout(holdTimer.current);
      if (streamTimer.current) clearInterval(streamTimer.current);
    },
    [],
  );

  // Keys are rendered by a plain function, not a component declared in this
  // body: a component type re-created every render made React remount all
  // 33 keys on every state change (each keypress, each streamed character),
  // replaying the entrance and blanking the board mid-glyf. The stagger
  // delay applies only before first commit so whileTap never lags.
  const entered = useRef(false);
  useEffect(() => {
    entered.current = true;
  }, []);

  let keySeq = 0;
  const renderKey = (k: string, label?: string, className = "") => {
    const i = keySeq++;
    return (
      <motion.button
        key={k}
        type="button"
        aria-label={k}
        initial={{ opacity: 0, scale: 0.6, y: 10 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{
          delay: entered.current ? 0 : 0.35 + i * 0.016,
          type: "spring",
          stiffness: 500,
          damping: 28,
        }}
        whileTap={{ scale: 0.93 }}
        className={[
          "key",
          className,
          pressed.has(k) ? "pressed" : "",
          charging === k ? "charging" : "",
          fired === k ? "fired" : "",
        ]
          .filter(Boolean)
          .join(" ")}
        onPointerDown={(e) => {
          e.preventDefault();
          keyDown(k);
        }}
        onPointerUp={(e) => {
          e.preventDefault();
          keyUp(k);
        }}
        onPointerLeave={() => {
          if (pressed.has(k)) keyUp(k);
        }}
      >
        {label ?? k.toUpperCase()}
        {BOUND[k] && <span className="dot" />}
        {BOUND[k] && <span className="ring" />}
      </motion.button>
    );
  };

  return (
    <div className="demo" id="demo">
      {/* On wide screens this is a phone at real keyboard scale; on a phone
          the frame melts away — the visitor's own device is the frame. */}
      <div className="phone">
        <div className="phone-screen">
          <div className="phone-status" aria-hidden>
            <span className="phone-time">9:41</span>
            <span className="phone-icons">
              <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor">
                <rect x="0" y="7" width="3" height="4" rx="0.9" />
                <rect x="4.6" y="4.8" width="3" height="6.2" rx="0.9" />
                <rect x="9.2" y="2.4" width="3" height="8.6" rx="0.9" />
                <rect x="13.8" y="0" width="3" height="11" rx="0.9" />
              </svg>
              <svg width="15" height="11" viewBox="0 0 15 11" fill="currentColor">
                <path d="M7.5 2.1c2.2 0 4.2.83 5.72 2.2l1.1-1.17A9.9 9.9 0 0 0 7.5.5 9.9 9.9 0 0 0 .68 3.13l1.1 1.17A8.3 8.3 0 0 1 7.5 2.1z" />
                <path d="M7.5 5.25c1.33 0 2.54.5 3.46 1.3l1.1-1.17A6.7 6.7 0 0 0 7.5 3.65a6.7 6.7 0 0 0-4.56 1.73l1.1 1.17a5.1 5.1 0 0 1 3.46-1.3z" />
                <path d="M7.5 8.4c.47 0 .9.17 1.23.44L7.5 10.5 6.27 8.84c.33-.27.76-.44 1.23-.44z" />
              </svg>
              <svg width="25" height="12" viewBox="0 0 25 12" fill="currentColor">
                <rect x="0.5" y="0.5" width="21" height="11" rx="3.2" fill="none" stroke="currentColor" opacity="0.38" />
                <rect x="2" y="2" width="18" height="8" rx="1.9" />
                <path d="M23 4v4c.75-.3 1.3-1.05 1.3-2S23.75 4.3 23 4z" opacity="0.4" />
              </svg>
            </span>
          </div>
          <div className="screen">
            <div className="label">
              {running ? (
                <>
                  <span className="run-dot" /> {running}…
                </>
              ) : (
                "Message"
              )}
            </div>
            <div className="text">
              {text}
              <span className="caret" />
            </div>
          </div>

          <div className="kb" data-kb-theme={theme === "glass" ? undefined : theme}>
            <div className="kb-toolbar">
              <motion.button
                type="button"
                className={`gpill ${surface === "bar" ? "open" : ""}`}
                onClick={() => openSurface("bar")}
                whileTap={{ scale: 0.92 }}
                aria-label="Glyf bar"
              >
                g
              </motion.button>
              <button
                type="button"
                className="ticon"
                aria-label="Search"
                onClick={() =>
                  document.querySelector(".ss")?.scrollIntoView({ behavior: "smooth", block: "center" })
                }
              >
                <svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
                  <circle cx="8.6" cy="8.6" r="5.3" />
                  <path d="M12.8 12.8 L17 17" />
                </svg>
              </button>
              <button
                type="button"
                className={`ticon ${surface === "clip" ? "on" : ""}`}
                aria-label="Clipboard"
                onClick={() => openSurface("clip")}
              >
                <svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
                  <rect x="4" y="4" width="12" height="14" rx="2.4" />
                  <rect x="7.4" y="2" width="5.2" height="3.6" rx="1.4" />
                </svg>
              </button>
              <button
                type="button"
                className={`ticon ${surface === "vault" ? "on" : ""}`}
                aria-label="Vault"
                onClick={() => openSurface("vault")}
              >
                <svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
                  <rect x="2.4" y="4.4" width="15.2" height="11.2" rx="2.4" />
                  <circle cx="7" cy="9.4" r="1.7" />
                  <path d="M11.4 8 h3.4 M11.4 11.4 h3.4" />
                </svg>
              </button>
              <button
                type="button"
                className={`ticon ${surface === "emoji" ? "on" : ""}`}
                aria-label="Emoji"
                onClick={() => openSurface("emoji")}
              >
                <svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
                  <circle cx="10" cy="10" r="7.4" />
                  <circle cx="7.4" cy="8.4" r="0.4" fill="currentColor" />
                  <circle cx="12.6" cy="8.4" r="0.4" fill="currentColor" />
                  <path d="M6.8 11.6 a4 3.4 0 0 0 6.4 0" />
                </svg>
              </button>
            </div>

            <AnimatePresence>
              {surface && surface !== "bar" && (
                <motion.div
                  className="kb-surface"
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ type: "spring", stiffness: 380, damping: 34 }}
                >
                  {surface === "clip" &&
                    CLIPS.map((c) => (
                      <button key={c} type="button" className="kb-chipcard" onClick={() => insertFromSurface(c)}>
                        {c}
                      </button>
                    ))}
                  {surface === "vault" &&
                    VAULT.map((v) => (
                      <button key={v.label} type="button" className="kb-chipcard" onClick={() => insertFromSurface(v.value)}>
                        <b>{v.label}</b> {v.value}
                      </button>
                    ))}
                  {surface === "emoji" && (
                    <div className="kb-emojirow">
                      {EMOJI.map((e) => (
                        <button key={e} type="button" onClick={() => insertFromSurface(e)}>
                          {e}
                        </button>
                      ))}
                    </div>
                  )}
                </motion.div>
              )}

              {surface === "bar" && (
                <motion.div
                  className="kb-bar"
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ type: "spring", stiffness: 380, damping: 34 }}
                >
                  <div className="kb-bar-pill">
                    <span className="kb-bar-g">g</span>
                    <span className="kb-bar-prompt">
                      {barPrompt || <em>Tell Glyf what to do…</em>}
                      <span className="caret light" />
                    </span>
                    <button type="button" className="kb-bar-go" onClick={runBar} aria-label="Run">
                      ↵
                    </button>
                  </div>
                  <div className="kb-bar-hints">
                    {["make it formal", "add emojis", "in spanish", "make it rhyme"].map((h) => (
                      <button
                        key={h}
                        type="button"
                        onClick={() => {
                          setBarPrompt(h);
                          setTimeout(() => runBarRef.current?.(), 60);
                        }}
                      >
                        {h}
                      </button>
                    ))}
                  </div>
                  <AnimatePresence>
                    {barResult !== null && (
                      <motion.div
                        className="kb-bar-result"
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0 }}
                      >
                        <p>
                          {barResult}
                          <span className="caret" />
                        </p>
                        <div className="kb-bar-actions">
                          <button
                            type="button"
                            className="primary"
                            onClick={() => {
                              setText(barResult);
                              setSurface(null);
                            }}
                          >
                            Replace
                          </button>
                          <button type="button" onClick={() => insertFromSurface(barResult)}>
                            Insert
                          </button>
                          <button type="button" onClick={() => setSurface(null)}>
                            ✕
                          </button>
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </motion.div>
              )}
            </AnimatePresence>

            <div className="kb-row">
              {ROW1.map((k) => renderKey(k))}
            </div>
            <div className="kb-row mid">
              {ROW2.map((k) => renderKey(k))}
            </div>
            <div className="kb-row">
              {renderKey("shift", "⇧", "special")}
              {ROW3.map((k) => renderKey(k))}
              {renderKey("backspace", "⌫", "special")}
            </div>
            <div className="kb-row">
              {renderKey("123", "123", "special")}
              {renderKey("space", "glyf", "space")}
              {renderKey("return", "↵", "special")}
            </div>
          </div>
        </div>
      </div>

      {/* skins live under the product, not above it */}
      <div className="theme-row" role="tablist" aria-label="Keyboard theme">
        {THEMES.map((t) => (
          <button
            key={t.id}
            type="button"
            className={`theme-pill ${theme === t.id ? "active" : ""}`}
            onClick={() => setTheme(t.id)}
          >
            <span className="theme-swatch" style={{ background: t.swatch }} />
            {t.label}
          </button>
        ))}
      </div>
    </div>
  );
}
