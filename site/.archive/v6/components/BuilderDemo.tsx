"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useCallback, useEffect, useRef, useState } from "react";
import { CalendarIcon, CoinIcon, SunIcon, WandIcon } from "./Icons";

/**
 * The brand thesis, playable: pick a tool, it binds to a key (dot pops),
 * the key "holds" itself and the result streams into a message.
 */

type Tool = {
  id: string;
  icon: React.ReactNode;
  label: string;
  key: string;
  result: string;
};

const TOOLS: Tool[] = [
  { id: "wx", icon: <SunIcon />, label: "Weather", key: "W", result: "Bengaluru right now: 24° and clear — carry nothing." },
  { id: "cal", icon: <CalendarIcon />, label: "Calendar", key: "C", result: "Free after 4 — want to do 4:30?" },
  { id: "btc", icon: <CoinIcon />, label: "Crypto", key: "B", result: "BTC $123,450 · up 2.4% today" },
  { id: "tone", icon: <WandIcon />, label: "Rewrite", key: "R", result: "Sounds great — let's lock it in for Friday!" },
];

const KEYS = ["Q", "W", "E", "R", "C", "B", "N", "M"];

export default function BuilderDemo() {
  const [tool, setTool] = useState<Tool>(TOOLS[0]);
  const [phase, setPhase] = useState<"pick" | "bound" | "hold" | "typed">("pick");
  const [typed, setTyped] = useState("");
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const [userDrove, setUserDrove] = useState(false);

  const clear = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };

  const run = useCallback((t: Tool) => {
    clear();
    setTool(t);
    setPhase("pick");
    setTyped("");
    timers.current.push(setTimeout(() => setPhase("bound"), 700));
    timers.current.push(setTimeout(() => setPhase("hold"), 1650));
    timers.current.push(
      setTimeout(() => {
        setPhase("typed");
        for (let i = 1; i <= t.result.length; i++) {
          timers.current.push(setTimeout(() => setTyped(t.result.slice(0, i)), i * 17));
        }
      }, 2350),
    );
  }, []);

  useEffect(() => {
    run(TOOLS[0]);
    return clear;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Rotate tools until the visitor picks one.
  useEffect(() => {
    if (userDrove) return;
    const next = TOOLS[(TOOLS.findIndex((t) => t.id === tool.id) + 1) % TOOLS.length];
    const cycle = setTimeout(() => run(next), 6400);
    return () => clearTimeout(cycle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tool, userDrove]);

  return (
    <div className="bd">
      <div className="bd-tools">
        {TOOLS.map((t) => (
          <motion.button
            key={t.id}
            type="button"
            className={`bd-tool ${tool.id === t.id ? "active" : ""}`}
            onClick={() => {
              setUserDrove(true);
              run(t);
            }}
            whileHover={{ y: -2 }}
            whileTap={{ scale: 0.95 }}
          >
            <span className="bd-ico">{t.icon}</span>
            {t.label}
          </motion.button>
        ))}
      </div>

      <div className="bd-stage">
        <div className="bd-keys">
          {KEYS.map((k) => {
            const isTarget = k === tool.key;
            const lit = isTarget && phase !== "pick";
            const holding = isTarget && phase === "hold";
            return (
              <motion.span
                key={k}
                className={`bd-key ${lit ? "lit" : ""} ${holding ? "holding" : ""}`}
                animate={
                  holding
                    ? { scale: [1, 0.92, 1.04, 1] }
                    : lit && phase === "bound"
                      ? { scale: [1, 1.14, 1] }
                      : { scale: 1 }
                }
                transition={{ duration: 0.5 }}
              >
                {k}
                <AnimatePresence>
                  {lit && (
                    <motion.i
                      className="bd-dot"
                      initial={{ scale: 0, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      exit={{ scale: 0, opacity: 0 }}
                      transition={{ type: "spring", stiffness: 600, damping: 18 }}
                    />
                  )}
                </AnimatePresence>
                {holding && <span className="bd-ring" />}
              </motion.span>
            );
          })}
        </div>

        <div className="bd-out">
          <span className="bd-out-label">Message</span>
          <div className="bd-out-body">
          <AnimatePresence mode="wait">
            {phase === "pick" && (
              <motion.span
                key="p1"
                className="bd-step"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
              >
                {tool.label} →
              </motion.span>
            )}
            {phase === "bound" && (
              <motion.span
                key="p2"
                className="bd-step"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
              >
                bound to <b className="bd-kb-chip">{tool.key}</b>
              </motion.span>
            )}
            {phase === "hold" && (
              <motion.span
                key="p3"
                className="bd-step"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
              >
                holding {tool.key}…
              </motion.span>
            )}
            {phase === "typed" && (
              <motion.span
                key="p4"
                className="bd-result"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
              >
                {typed}
                <span className="caret" />
              </motion.span>
            )}
          </AnimatePresence>
          </div>
        </div>
      </div>
    </div>
  );
}
