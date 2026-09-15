"use client";

import { motion, useMotionValue, useSpring } from "framer-motion";
import { useEffect, useState } from "react";

/**
 * The glyf dot as your cursor: an ink dot that springs after the mouse,
 * blooming into an accent ring over anything pressable. Fine pointers
 * only — touch devices never see it.
 */

const PRESSABLE = "button, a, .key, .chip, .theme-pill, .ss-card, .ss-chip, " +
  ".gm-tile, .bd-tool, .pr-card, input, .fs-card";

export default function CursorGlyf() {
  const x = useMotionValue(-100);
  const y = useMotionValue(-100);
  const sx = useSpring(x, { stiffness: 650, damping: 45, mass: 0.6 });
  const sy = useSpring(y, { stiffness: 650, damping: 45, mass: 0.6 });
  const [mode, setMode] = useState<"dot" | "ring" | "down">("dot");
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    if (!window.matchMedia("(pointer: fine)").matches) return;
    setEnabled(true);
    document.documentElement.classList.add("glyf-cursor");

    const move = (e: PointerEvent) => {
      x.set(e.clientX);
      y.set(e.clientY);
    };
    const over = (e: PointerEvent) => {
      const t = e.target as HTMLElement | null;
      setMode(t?.closest(PRESSABLE) ? "ring" : "dot");
    };
    const down = () => setMode("down");
    const up = (e: PointerEvent) => {
      const t = e.target as HTMLElement | null;
      setMode(t?.closest(PRESSABLE) ? "ring" : "dot");
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerover", over, { passive: true });
    window.addEventListener("pointerdown", down, { passive: true });
    window.addEventListener("pointerup", up, { passive: true });
    return () => {
      document.documentElement.classList.remove("glyf-cursor");
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerover", over);
      window.removeEventListener("pointerdown", down);
      window.removeEventListener("pointerup", up);
    };
  }, [x, y]);

  if (!enabled) return null;

  return (
    <motion.div
      className="cursor-glyf"
      style={{ x: sx, y: sy }}
      animate={mode}
      variants={{
        dot: { width: 10, height: 10, opacity: 1 },
        ring: { width: 34, height: 34, opacity: 1 },
        down: { width: 22, height: 22, opacity: 1 },
      }}
      transition={{ type: "spring", stiffness: 520, damping: 30 }}
    >
      <motion.span
        className="cursor-core"
        variants={{
          dot: { scale: 1, opacity: 1 },
          ring: { scale: 0.42, opacity: 1 },
          down: { scale: 0.65, opacity: 1 },
        }}
      />
    </motion.div>
  );
}
