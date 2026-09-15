"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useState } from "react";
import {
  CalendarIcon,
  ClipboardIcon,
  NotesIcon,
  PacksIcon,
  VaultIcon,
} from "./Icons";

/** The g menu, clickable: every surface that lives inside the keyboard. */

type Pane = "vault" | "notes" | "clipboard" | "calendar" | "packs";

const TILES: { id: Pane; label: string; icon: React.ReactNode }[] = [
  { id: "calendar", label: "Calendar", icon: <CalendarIcon /> },
  { id: "vault", label: "Vault", icon: <VaultIcon /> },
  { id: "clipboard", label: "Clipboard", icon: <ClipboardIcon /> },
  { id: "notes", label: "Notes", icon: <NotesIcon /> },
  { id: "packs", label: "Packs", icon: <PacksIcon /> },
];

export default function GMenu() {
  const [pane, setPane] = useState<Pane>("calendar");
  const [userDrove, setUserDrove] = useState(false);

  useEffect(() => {
    if (userDrove) return;
    const order = TILES.map((t) => t.id);
    const next = order[(order.indexOf(pane) + 1) % order.length];
    const t = setTimeout(() => setPane(next), 3400);
    return () => clearTimeout(t);
  }, [pane, userDrove]);

  return (
    <div className="gm">
      <div className="gm-rail">
        <div className="gm-gpill">g</div>
        {TILES.map((t) => (
          <motion.button
            key={t.id}
            type="button"
            className={`gm-tile ${pane === t.id ? "active" : ""}`}
            onClick={() => {
              setUserDrove(true);
              setPane(t.id);
            }}
            whileHover={{ y: -2 }}
            whileTap={{ scale: 0.95 }}
          >
            <span className="gm-ico">{t.icon}</span>
            {t.label}
          </motion.button>
        ))}
      </div>

      <div className="gm-pane">
        <AnimatePresence mode="wait">
          <motion.div
            key={pane}
            initial={{ opacity: 0, y: 14, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -10, scale: 0.99, transition: { duration: 0.14 } }}
            transition={{ type: "spring", stiffness: 380, damping: 30 }}
            className="gm-pane-inner"
          >
            {pane === "calendar" && <Calendar />}
            {pane === "vault" && <Vault />}
            {pane === "clipboard" && <Clip />}
            {pane === "notes" && <Notes />}
            {pane === "packs" && <Packs />}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}

function Calendar() {
  const dots = [3, 9, 12, 17, 21, 26];
  return (
    <div className="gm-cal">
      <div className="gm-cal-head">
        <b>September</b>
        <span className="gm-badge">4:30 free</span>
      </div>
      <div className="gm-cal-grid">
        {Array.from({ length: 30 }, (_, i) => {
          const d = i + 1;
          return (
            <span key={d} className={`gm-day ${d === 13 ? "today" : ""}`}>
              {d}
              {dots.includes(d) && <i />}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function Vault() {
  return (
    <div className="gm-list">
      <div className="gm-card"><b>Home</b><i>Flat 4B, Indiranagar, Bengaluru</i></div>
      <div className="gm-card"><b>UPI</b><i>arpit@okbank</i></div>
      <div className="gm-card accent"><b>;sig</b><i>— Arpit · arpit@tryglyf.com</i></div>
    </div>
  );
}

function Clip() {
  return (
    <div className="gm-list">
      <div className="gm-card"><b>2 min ago</b><i>the figma link from standup</i></div>
      <div className="gm-card"><b>14 min ago</b><i>OTP screenshots never land here</i></div>
      <div className="gm-card"><b>1 hr ago</b><i>flight PNR · QR7GH2</i></div>
    </div>
  );
}

function Notes() {
  return (
    <div className="gm-list">
      <div className="gm-card"><b>Standup</b><i>demo the builder, ask about Friday</i></div>
      <div className="gm-card"><b>Gift ideas</b><i>mechanical keyboard, film camera</i></div>
    </div>
  );
}

function Packs() {
  return (
    <div className="gm-list">
      <div className="gm-card"><b>Writer</b><i>Polish · Tighten · Tone</i></div>
      <div className="gm-card"><b>Operator</b><i>Live answers while you type</i></div>
      <div className="gm-card"><b>Social</b><i>Replies that land</i></div>
    </div>
  );
}
