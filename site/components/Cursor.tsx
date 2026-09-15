"use client";

import { useEffect, useRef } from "react";

/** Caret → keycap. A text caret that follows the mouse 1:1 (and grows to the
 *  size of the type under it); over anything clickable it snaps into a keycap
 *  outline around that element, and sinks when you press. Mouse only;
 *  touch devices and reduced-motion visitors keep the system cursor. */

const CLICKABLE = 'a, button, summary, label, select, [role="tab"], [role="button"]';
const TEXT_INPUT = 'input:not([type="checkbox"]):not([type="radio"]):not([type="submit"]), textarea';

export default function Cursor() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!matchMedia("(pointer: fine)").matches || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const el = ref.current;
    if (!el) return;
    const html = document.documentElement;
    html.classList.add("has-cursor");

    let mx = -100, my = -100;
    let x = -100, y = -100, w = 2, h = 22, r = 1;
    let caretH = 22;
    let target: HTMLElement | null = null;
    let raf = 0;
    let last = performance.now();
    let idle = 0;

    const loop = (now: number) => {
      const dt = Math.min(64, now - last);
      last = now;
      const k = 1 - Math.pow(1 - 0.3, dt / 16.7);
      let tx: number, ty: number, tw: number, th: number, tr: number;
      if (target && target.isConnected) {
        const b = target.getBoundingClientRect();
        const pad = Math.max(4, Math.min(8, b.height * 0.14));
        const radius = parseFloat(getComputedStyle(target).borderTopLeftRadius) || 8;
        tw = b.width + pad * 2;
        th = b.height + pad * 2;
        tr = Math.min(th / 2, radius + pad);
        tx = b.left - pad + (mx - (b.left + b.width / 2)) * 0.06;
        ty = b.top - pad + (my - (b.top + b.height / 2)) * 0.06;
        x += (tx - x) * k;
        y += (ty - y) * k;
      } else {
        target = null;
        tw = 2;
        th = caretH;
        tr = 1;
        tx = mx - 1;
        ty = my - th / 2;
        const snap = Math.abs(w - tw) < 1 && Math.abs(h - th) < 1;
        x = snap ? tx : x + (tx - x) * Math.max(k, 0.55);
        y = snap ? ty : y + (ty - y) * Math.max(k, 0.55);
      }
      w += (tw - w) * k;
      h += (th - h) * k;
      r += (tr - r) * k;
      el.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      el.style.width = `${w}px`;
      el.style.height = `${h}px`;
      el.style.borderRadius = `${r}px`;
      if (!target && now - idle > 520) el.classList.add("blink");
      raf = requestAnimationFrame(loop);
    };

    const aim = (node: Element | null) => {
      const hit = node?.closest?.(CLICKABLE) as HTMLElement | null;
      const typing = node?.closest?.(TEXT_INPUT);
      const next = hit && !typing && !(hit as HTMLButtonElement).disabled ? hit : null;
      if (next !== target) {
        target = next;
        el.classList.toggle("cap", !!target);
      }
      if (!target && node) {
        const size = parseFloat(getComputedStyle(node as Element).fontSize) || 16;
        caretH = Math.max(18, Math.min(110, size * 1.08));
      }
    };

    const move = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      mx = e.clientX;
      my = e.clientY;
      idle = performance.now();
      el.classList.remove("blink");
      if (!el.classList.contains("on")) {
        el.classList.add("on");
        x = mx;
        y = my;
      }
    };
    const over = (e: PointerEvent) => aim(e.target as Element);
    const down = () => el.classList.add("down");
    const up = () => el.classList.remove("down");
    const leave = (e: MouseEvent) => {
      if (!e.relatedTarget) el.classList.remove("on");
    };
    const scroll = () => aim(document.elementFromPoint(mx, my));

    window.addEventListener("pointermove", move, { passive: true });
    document.addEventListener("pointerover", over, { passive: true });
    window.addEventListener("pointerdown", down, { passive: true });
    window.addEventListener("pointerup", up, { passive: true });
    document.addEventListener("mouseout", leave);
    window.addEventListener("scroll", scroll, { passive: true });
    raf = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(raf);
      html.classList.remove("has-cursor");
      window.removeEventListener("pointermove", move);
      document.removeEventListener("pointerover", over);
      window.removeEventListener("pointerdown", down);
      window.removeEventListener("pointerup", up);
      document.removeEventListener("mouseout", leave);
      window.removeEventListener("scroll", scroll);
    };
  }, []);

  return <div ref={ref} className="cursor" aria-hidden />;
}
