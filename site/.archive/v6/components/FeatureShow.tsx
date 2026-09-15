"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useState } from "react";

/** Feature cards that DEMO themselves — no explainer copy, just loops. */

export default function FeatureShow() {
  return (
    <div className="fs-grid">
      <Card title="Fixes itself.">
        <ProofLoop />
      </Card>
      <Card title=";sig → everything">
        <VaultLoop />
      </Card>
      <Card title="Any skin.">
        <ThemeLoop />
      </Card>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <motion.div
      className="fs-card"
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ type: "spring", stiffness: 260, damping: 30 }}
      whileHover={{ y: -4 }}
    >
      <div className="fs-demo">{children}</div>
      <h3>{title}</h3>
    </motion.div>
  );
}

/* 1 — proofread: sloppy line morphs clean, forever */

function ProofLoop() {
  const [fixed, setFixed] = useState(false);
  useEffect(() => {
    const t = setInterval(() => setFixed((f) => !f), 2600);
    return () => clearInterval(t);
  }, []);
  return (
    <div className="fs-proof">
      <motion.span
        className="fs-keycap-mini"
        animate={fixed ? { scale: [1, 0.86, 1] } : { scale: 1 }}
        transition={{ duration: 0.34, ease: "easeOut" }}
      >
        P<span className="dot" />
      </motion.span>
      <AnimatePresence mode="wait">
        <motion.span
          key={fixed ? "b" : "a"}
          className={`fs-proof-text ${fixed ? "ok" : ""}`}
          initial={{ opacity: 0, y: 8, filter: "blur(3px)" }}
          animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          exit={{ opacity: 0, y: -8, filter: "blur(3px)" }}
          transition={{ duration: 0.3 }}
        >
          {fixed ? "The meeting is at 3." : "teh meeting si at 3"}
        </motion.span>
      </AnimatePresence>
    </div>
  );
}

/* 2 — vault: ;sig expands into the real thing */

function VaultLoop() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const t = setInterval(() => setOpen((o) => !o), 2600);
    return () => clearInterval(t);
  }, []);
  return (
    <div className="fs-vault">
      <AnimatePresence mode="wait">
        {open ? (
          <motion.div
            key="sig"
            className="fs-sig"
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.96 }}
            transition={{ type: "spring", stiffness: 420, damping: 26 }}
          >
            <b>Arpit</b>
            <i>arpit@tryglyf.com · +91 98••• ••210</i>
          </motion.div>
        ) : (
          <motion.code
            key="trigger"
            className="fs-trigger"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
          >
            ;sig<span className="caret" />
          </motion.code>
        )}
      </AnimatePresence>
    </div>
  );
}

/* 3 — themes: a strip of keys cycling skins */

const SKINS = [
  { bg: "linear-gradient(135deg,#7C5CFF,#EC6ADE)", key: "rgba(255,255,255,0.3)", ink: "#fff" },
  { bg: "linear-gradient(135deg,#3D8BFF,#41E0C8)", key: "rgba(255,255,255,0.3)", ink: "#fff" },
  { bg: "linear-gradient(135deg,#FF7847,#FFC53D)", key: "rgba(255,255,255,0.32)", ink: "#fff" },
  { bg: "#15161b", key: "rgba(255,255,255,0.18)", ink: "#fff" },
];

function ThemeLoop() {
  const [i, setI] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setI((v) => (v + 1) % SKINS.length), 1900);
    return () => clearInterval(t);
  }, []);
  const s = SKINS[i];
  return (
    // Gradients can't be interpolated (framer warns and snaps anyway), so the
    // ground swaps via style; the keys' rgba fills still animate.
    <div className="fs-theme" style={{ background: s.bg }}>
      {["G", "L", "Y", "F"].map((c, n) => (
        <motion.span
          key={c}
          className="fs-theme-key"
          animate={{ background: s.key, color: s.ink }}
          transition={{ duration: 0.5 }}
        >
          {c}
          {n === 0 && <span className="dot" />}
        </motion.span>
      ))}
    </div>
  );
}
