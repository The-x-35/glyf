"use client";

import { motion, useScroll, useTransform } from "framer-motion";
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { POS } from "./kb/data";

/** The Glyf keyboard behind the hero: faint, lying back in perspective,
 *  quietly typing the tagline, firing a glyf now and then, and pressing
 *  whatever you press on your real keyboard. Fades out past the hero.
 *  Decorative only: no input, hidden from assistive tech. */

type Key = { id: string; pos: string; span: number; start?: number; label: ReactNode; fn?: boolean; dot?: boolean };

const BOUND = new Set(["q", "w", "e", "r", "t", "p", "s", "j", "x", "c"]);
const letters = (row: number, keys: string, first?: number): Key[] =>
  [...keys].map((k, i) => ({ id: k, pos: `${row}-${k}`, span: 2, start: i === 0 ? first : undefined, label: k, dot: BOUND.has(k) }));

const KEYS: Key[] = [
  ...letters(0, "qwertyuiop"),
  ...letters(1, "asdfghjkl", 2),
  { id: "shift", pos: "2-shift", span: 3, label: "⇧", fn: true },
  ...letters(2, "zxcvbnm"),
  { id: "del", pos: "2-backspace", span: 3, label: "⌫", fn: true },
  { id: "123", pos: "3-mode", span: 3, label: "123", fn: true },
  { id: "emoji", pos: "3-emoji", span: 2, label: "☺", fn: true },
  { id: "space", pos: "3-space", span: 10, label: "glyf" },
  { id: ".", pos: "3-.", span: 2, label: ".", fn: true },
  { id: "return", pos: "3-return", span: 3, label: "⏎", fn: true },
];

const PHRASE = "type less glyf more";
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export default function BackdropKeys() {
  const [down, setDown] = useState<string | null>(null);
  const [held, setHeld] = useState<Set<string>>(() => new Set());
  const [ripple, setRipple] = useState(0);
  const typedAt = useRef(0);
  // Hero only: it tilts back and fades away as the headline scrolls off.
  const { scrollY } = useScroll();
  const reach = () => (typeof window === "undefined" ? 800 : window.innerHeight * 0.65);
  const fade = useTransform(scrollY, (y) => Math.max(0, 1 - y / reach()));
  const tilt = useTransform(scrollY, (y) => 52 + Math.min(1, y / reach()) * 10);
  const lift = useTransform(scrollY, (y) => Math.min(1, y / reach()) * 70);
  const shown = useTransform(fade, (o) => (o <= 0.01 ? "hidden" : "visible"));

  // Your real keyboard presses the same keys back here. Hold space and it fires a glyf.
  useEffect(() => {
    const idOf = (e: KeyboardEvent) => {
      const k = e.key;
      if (/^[a-z]$/i.test(k)) return k.toLowerCase();
      if (k === " ") return "space";
      if (k === "Backspace") return "del";
      if (k === "Enter") return "return";
      if (k === "Shift") return "shift";
      if (k === ".") return ".";
      if (/^[0-9]$/.test(k)) return "123";
      return null;
    };
    let spaceTimer = 0;
    const onDown = (e: KeyboardEvent) => {
      const id = idOf(e);
      if (!id) return;
      typedAt.current = Date.now();
      setDown(null);
      setHeld((h) => (h.has(id) ? h : new Set(h).add(id)));
      if (id === "space" && !e.repeat) spaceTimer = window.setTimeout(() => setRipple((n) => n + 1), 480);
    };
    const onUp = (e: KeyboardEvent) => {
      const id = idOf(e);
      if (!id) return;
      if (id === "space") clearTimeout(spaceTimer);
      setHeld((h) => {
        if (!h.has(id)) return h;
        const next = new Set(h);
        next.delete(id);
        return next;
      });
    };
    const clear = () => setHeld(new Set());
    window.addEventListener("keydown", onDown);
    window.addEventListener("keyup", onUp);
    window.addEventListener("blur", clear);
    return () => {
      clearTimeout(spaceTimer);
      window.removeEventListener("keydown", onDown);
      window.removeEventListener("keyup", onUp);
      window.removeEventListener("blur", clear);
    };
  }, []);

  useEffect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let alive = true;
    const wait = async (ms: number) => {
      await sleep(ms);
      // pause the ambient typing while a tab is hidden or the visitor is typing
      while (alive && (document.hidden || window.scrollY > window.innerHeight || Date.now() - typedAt.current < 4000)) await sleep(400);
    };
    void (async () => {
      await wait(1400);
      while (alive) {
        for (const ch of PHRASE) {
          if (!alive) return;
          setDown(ch === " " ? "space" : ch);
          await wait(120);
          setDown(null);
          await wait(80 + Math.random() * 140);
        }
        await wait(700);
        setDown("space");
        await wait(650);
        setDown(null);
        setRipple((n) => n + 1);
        await wait(5200);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const origin = POS.abc["3-space"];

  return (
    <motion.div className="backdrop-keys" style={{ opacity: fade, visibility: shown }} aria-hidden>
      <motion.div className="backdrop-keys-board" style={{ rotateX: tilt, y: lift }}>
        {KEYS.map((k) => {
          const p = POS.abc[k.pos];
          const delay = p ? Math.hypot(p[0] - origin[0], (p[1] - origin[1]) * 1.2) * 34 : 0;
          return (
            <span
              key={k.id}
              className={`hk${k.fn ? " fn" : ""}${k.id === "space" ? " space" : ""}${down === k.id || held.has(k.id) ? " down" : ""}`}
              style={{ gridColumn: `${k.start ? `${k.start} / ` : ""}span ${k.span}` } as CSSProperties}
            >
              {k.label}
              {k.dot && <i className="hk-dot" />}
              {ripple > 0 && k.id !== "space" && <b key={ripple} className="hk-tint" style={{ animationDelay: `${delay}ms` }} />}
            </span>
          );
        })}
      </motion.div>
    </motion.div>
  );
}
