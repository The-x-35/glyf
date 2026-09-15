"use client";

import { useEffect, useRef } from "react";

/** Easter egg: really hold the spacebar on the last screen. */
const RICK = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const HOLD_MS = 1600;

export default function SpaceEgg() {
  const probe = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const section = probe.current?.closest("section");
    if (!section) return;
    let inView = false;
    let timer = 0;
    const io = new IntersectionObserver(([e]) => (inView = e.intersectionRatio >= 0.5), { threshold: [0, 0.5, 1] });
    io.observe(section);

    const typing = (t: EventTarget | null) => {
      const el = t as HTMLElement | null;
      return !!el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));
    };
    const onDown = (e: KeyboardEvent) => {
      if (e.key !== " " || !inView || typing(e.target)) return;
      e.preventDefault();
      if (e.repeat || timer) return;
      timer = window.setTimeout(() => {
        timer = 0;
        window.open(RICK, "_blank", "noopener,noreferrer");
      }, HOLD_MS);
    };
    const onUp = (e: KeyboardEvent) => {
      if (e.key !== " ") return;
      clearTimeout(timer);
      timer = 0;
    };
    window.addEventListener("keydown", onDown);
    window.addEventListener("keyup", onUp);
    return () => {
      clearTimeout(timer);
      io.disconnect();
      window.removeEventListener("keydown", onDown);
      window.removeEventListener("keyup", onUp);
    };
  }, []);

  return <span ref={probe} hidden />;
}
