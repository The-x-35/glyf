"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useRef, useState } from "react";

/**
 * The SecretScanner, live: the vault visibly REFUSES a card number, then
 * accepts a normal thing. The privacy stance as a demo, not a paragraph.
 */

const CARD = "4242 4242 4242 4242";
const SAFE = "Flat 4B, Indiranagar";

export default function PrivacyDemo() {
  const [typed, setTyped] = useState("");
  const [state, setState] = useState<"typing" | "refused" | "saved">("typing");
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    const clear = () => {
      timers.current.forEach(clearTimeout);
      timers.current = [];
    };
    const loop = () => {
      clear();
      setState("typing");
      setTyped("");
      for (let i = 1; i <= CARD.length; i++) {
        timers.current.push(setTimeout(() => setTyped(CARD.slice(0, i)), 300 + i * 46));
      }
      const t1 = 300 + CARD.length * 46 + 350;
      timers.current.push(setTimeout(() => setState("refused"), t1));
      timers.current.push(
        setTimeout(() => {
          setState("typing");
          setTyped("");
          for (let i = 1; i <= SAFE.length; i++) {
            timers.current.push(setTimeout(() => setTyped(SAFE.slice(0, i)), i * 46));
          }
          timers.current.push(setTimeout(() => setState("saved"), SAFE.length * 46 + 380));
        }, t1 + 1900),
      );
      timers.current.push(setTimeout(loop, t1 + 1900 + SAFE.length * 46 + 2600));
    };
    loop();
    return clear;
  }, []);

  return (
    <div className="pv">
      <motion.div
        className={`pv-field ${state}`}
        animate={state === "refused" ? { x: [0, -9, 9, -6, 6, -2, 0] } : { x: 0 }}
        transition={{ duration: 0.45 }}
      >
        <span className="pv-label">Add to vault</span>
        <span className="pv-text">
          {typed}
          <span className="caret" />
        </span>
        <AnimatePresence>
          {state === "refused" && (
            <motion.span
              key="no"
              className="pv-flag no"
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
            >
              Card numbers can't be saved
            </motion.span>
          )}
          {state === "saved" && (
            <motion.span
              key="ok"
              className="pv-flag ok"
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={{ type: "spring", stiffness: 500, damping: 22 }}
            >
              ✓ Saved on this phone
            </motion.span>
          )}
        </AnimatePresence>
      </motion.div>

      <div className="pv-chips">
        <span className="pv-chip">Vault: on-device AES</span>
        <span className="pv-chip">Contacts: never uploaded</span>
        <span className="pv-chip">No typing logs</span>
      </div>
    </div>
  );
}
