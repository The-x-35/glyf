"use client";

import { motion } from "framer-motion";
import BuilderDemo from "@/components/BuilderDemo";
import CursorGlyf from "@/components/CursorGlyf";
import FeatureShow from "@/components/FeatureShow";
import GlyfKeyboard from "@/components/GlyfKeyboard";
import GMenu from "@/components/GMenu";
import Pricing from "@/components/Pricing";
import PrivacyDemo from "@/components/PrivacyDemo";
import SearchSuite from "@/components/SearchSuite";
import Waitlist from "@/components/Waitlist";

/** Apple's motion: things arrive, quietly. No bounce, no stagger circus. */
const arrive = {
  initial: { opacity: 0, y: 18 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: "-90px" },
  transition: { duration: 0.6, ease: [0.25, 0.1, 0.25, 1] as const },
};

const rise = (delay: number) => ({
  initial: { opacity: 0, y: 18 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.7, delay, ease: [0.25, 0.1, 0.25, 1] as const },
});

const AppleMark = () => (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
    <path d="M17.05 12.53c-.03-2.9 2.37-4.29 2.48-4.36-1.35-1.97-3.45-2.24-4.2-2.27-1.79-.18-3.49 1.05-4.4 1.05-.9 0-2.3-1.02-3.79-1-1.95.03-3.74 1.13-4.74 2.87-2.02 3.5-.52 8.68 1.45 11.52.96 1.39 2.11 2.95 3.62 2.9 1.45-.06 2-.94 3.76-.94s2.25.94 3.79.91c1.56-.03 2.55-1.42 3.51-2.82 1.1-1.62 1.56-3.19 1.58-3.27-.03-.02-3.03-1.16-3.06-4.59zM14.16 4c.8-.97 1.34-2.32 1.19-3.66-1.15.05-2.55.77-3.38 1.73-.74.86-1.39 2.23-1.22 3.55 1.29.1 2.6-.65 3.41-1.62z" />
  </svg>
);

const PlayMark = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
    <path d="M3.6 1.8c-.36.38-.6.97-.6 1.73v16.94c0 .76.24 1.35.6 1.73l.1.09 9.49-9.49v-.22L3.7 1.71l-.1.09z" />
    <path d="M16.35 15.95l-3.16-3.16v-.22l3.16-3.16.07.04 3.75 2.13c1.07.6 1.07 1.6 0 2.21l-3.75 2.12-.07.04z" opacity=".75" />
    <path d="M16.42 15.9L13.19 12.7 3.6 22.2c.35.37.93.42 1.59.05l11.23-6.35z" opacity=".55" />
    <path d="M16.42 8.1L5.19 1.75C4.53 1.38 3.95 1.43 3.6 1.8l9.59 9.5 3.23-3.2z" opacity=".9" />
  </svg>
);

/**
 * Layout, from first principles:
 * · A keyboard is a portrait thing on a landscape screen — so the hero is a
 *   split, and the keyboard lives in a phone at real scale, not in a card.
 * · Sections alternate sides so the eye zig-zags instead of re-reading the
 *   same centred slide eight times. Headlines anchor left; only the two
 *   bookends (hero on small screens, the closing band) centre.
 * · Copy is unchanged. Layout carries the hierarchy, not new words.
 */
export default function Page() {
  return (
    <>
      <CursorGlyf />

      <nav className="nav">
        <div className="wrap nav-inner">
          <a className="wordmark" href="#top" aria-label="Glyf home">
            glyf<span className="dot" />
          </a>
          <div className="nav-links">
            <a href="#search">Search</a>
            <a href="#build">Build</a>
            <a href="#privacy">Privacy</a>
            <a href="#pricing">Pricing</a>
          </div>
          <a className="nav-cta" href="#get">Get Glyf</a>
        </div>
      </nav>

      {/* ── Hero: copy left, the live keyboard in a phone right ── */}
      <section className="hero" id="top">
        <div className="wrap split">
          <div className="split-copy">
            {/* One line, always: on two lines the raised brand dot collides
                with the "y" of "key" above it. */}
            <motion.h1 className="display" {...rise(0)}>
              Every key is a Glyf<span className="brand-dot" />
            </motion.h1>
            <motion.p className="lede" {...rise(0.08)}>
              Hold a key. It&apos;s already done.
            </motion.p>
            <motion.div className="actions" {...rise(0.16)}>
              <a className="pill" href="#get">Get Glyf</a>
              <a className="link" href="#search">See what it does</a>
            </motion.div>
            <motion.p className="note" {...rise(0.24)}>
              Hold P, T or U. Or press g.
            </motion.p>
          </div>
          <div className="split-media">
            <GlyfKeyboard />
          </div>
        </div>
      </section>

      {/* ── Search, on black: product left, words right ─────── */}
      <section className="band band--black" id="search">
        <div className="wrap split split--reverse">
          <motion.div className="split-copy" {...arrive}>
            <h2 className="headline">
              Search without
              <br />
              leaving the chat.
            </h2>
            <p className="lede">Google, YouTube, Maps and your contacts — inside the keys.</p>
          </motion.div>
          <div className="split-media">
            <SearchSuite />
          </div>
        </div>
      </section>

      {/* ── Builder ────────────────────────────────────────── */}
      <section className="band band--white" id="build">
        <div className="wrap split">
          <motion.div className="split-copy" {...arrive}>
            <h2 className="headline">Make any key yours.</h2>
            <p className="lede">Twenty-eight tools. Any letter. No setup.</p>
          </motion.div>
          <div className="split-media">
            <BuilderDemo />
          </div>
        </div>
      </section>

      {/* ── g menu ─────────────────────────────────────────── */}
      <section className="band band--grey" id="menu">
        <div className="wrap split split--reverse">
          <motion.div className="split-copy" {...arrive}>
            <h2 className="headline">Everything, under one button.</h2>
            <p className="lede">Calendar, vault, clipboard, notes and packs.</p>
          </motion.div>
          <div className="split-media">
            <GMenu />
          </div>
        </div>
      </section>

      {/* ── Feature tiles: one tall, two stacked ───────────── */}
      <section className="band band--white">
        <div className="wrap">
          <motion.h2 className="headline section-title" {...arrive}>
            It just does things.
          </motion.h2>
          <FeatureShow />
        </div>
      </section>

      {/* ── Privacy, on black ──────────────────────────────── */}
      <section className="band band--black" id="privacy">
        <div className="wrap split">
          <motion.div className="split-copy" {...arrive}>
            <h2 className="headline">
              Your secrets
              <br />
              never leave.
            </h2>
            <p className="lede">The vault is encrypted on your phone. Nothing is uploaded.</p>
          </motion.div>
          <div className="split-media">
            <PrivacyDemo />
          </div>
        </div>
      </section>

      {/* ── Pricing ────────────────────────────────────────── */}
      <section className="band band--grey" id="pricing">
        <div className="wrap">
          <motion.h2 className="headline section-title" {...arrive}>
            Start free.
          </motion.h2>
          <Pricing />
        </div>
      </section>

      {/* ── Get it: the closing bookend, centred ───────────── */}
      <section className="band band--white finale" id="get">
        <div className="wrap">
          <motion.div {...arrive}>
            <h2 className="display">
              Put a Glyf
              <br />
              under every key.
            </h2>
            <div className="store-row">
              <a className="store-btn" href="#" aria-label="Download on the App Store">
                <AppleMark />
                <span className="lines">
                  <span className="small">Download on the</span>
                  <br />
                  <span className="big">App Store</span>
                </span>
              </a>
              <a className="store-btn" href="#" aria-label="Get it on Google Play">
                <PlayMark />
                <span className="lines">
                  <span className="small">Get it on</span>
                  <br />
                  <span className="big">Google Play</span>
                </span>
              </a>
            </div>
            <Waitlist />
          </motion.div>
        </div>
      </section>

      <footer>
        <div className="wrap">
          <div className="footer-line">Made for thumbs.</div>
          <div className="footer-legal">
            <span>Copyright © {new Date().getFullYear()} Glyf. All rights reserved.</span>
            <span>iOS · Android</span>
          </div>
        </div>
      </footer>
    </>
  );
}
