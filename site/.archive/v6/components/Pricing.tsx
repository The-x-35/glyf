"use client";

import { motion } from "framer-motion";

const PLANS = [
  { name: "Free", price: "$0", note: "40 runs a day", cta: "Start" },
  { name: "Plus", price: "$4.99", note: "400 runs a day", cta: "Go Plus" },
  { name: "Max", price: "$19.99", note: "Unlimited", cta: "Go Max", hot: true },
];

export default function Pricing() {
  return (
    <div className="pr-grid">
      {PLANS.map((p, i) => (
        <motion.div
          key={p.name}
          className={`pr-card ${p.hot ? "hot" : ""}`}
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-70px" }}
          transition={{ type: "spring", stiffness: 260, damping: 30, delay: i * 0.07 }}
          whileHover={{ y: -5 }}
        >
          <div className="pr-name">{p.name}</div>
          <div className="pr-price">
            {p.price}
            {p.name !== "Free" && <span>/mo</span>}
          </div>
          <div className="pr-note">{p.note}</div>
          <a href="#get" className="pr-cta">{p.cta}</a>
        </motion.div>
      ))}
    </div>
  );
}
