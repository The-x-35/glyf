import { MagicBlockMark } from "./kb/brands";
import {
  CalendarCheckIcon,
  CalendarIcon,
  GifIcon,
  LinkIcon,
  PersonIcon,
  PinIcon,
  PlayRectIcon,
  SearchIcon,
  SparkIcon,
  SwapIcon,
  TranslateIcon,
  VideoIcon,
  WalletIcon,
} from "./kb/icons";

/** What Glyf does and what it works with, ahead of the chats that show it. */

/** Keys the app binds by default or that people bind first: all real targets. */
const BOUND = [
  { key: "C", label: "Calendar" },
  { key: "V", label: "Vault" },
  { key: "T", label: "Translate" },
  { key: "M", label: "Meet link" },
];

/** The strip's own tools, after Glyf's key. */
const TOOLS = [
  { icon: <SearchIcon />, label: "Search" },
  { icon: <PinIcon />, label: "Maps" },
  { icon: <CalendarIcon />, label: "Calendar" },
  { icon: <WalletIcon />, label: "Wallet" },
  { icon: <TranslateIcon />, label: "Translate" },
  { icon: <SparkIcon />, label: "AI" },
];

/** Answers that land in the strip instead of in another app. */
const ANSWERS = [
  { icon: <PinIcon />, text: "Bean & Byte Café", meta: "350 m" },
  { icon: <CalendarIcon />, text: "Demo call", meta: "Tomorrow 6:00 PM" },
  { icon: <span className="feat-cash">$</span>, text: "1 AAPL", meta: "$341.07" },
];

/** What the keyboard reaches today (Connected tools, the wallet, search). */
const WORKS_WITH = [
  { icon: <CalendarIcon />, name: "Google Calendar" },
  { icon: <VideoIcon />, name: "Google Meet" },
  { icon: <CalendarCheckIcon />, name: "Cal.com" },
  { icon: <LinkIcon />, name: "Calendly" },
  { icon: <MagicBlockMark />, name: "MagicBlock" },
  { icon: <WalletIcon />, name: "Solana wallet" },
  { icon: <SwapIcon />, name: "Jupiter" },
  { icon: <PinIcon />, name: "Google Maps" },
  { icon: <PlayRectIcon />, name: "YouTube" },
  { icon: <PersonIcon />, name: "Contacts" },
  { icon: <GifIcon />, name: "GIFs by KLIPY" },
];

const GlyfKey = () => (
  <span className="feat-g" aria-hidden>
    g<span className="feat-gdot" />
  </span>
);

export default function Features() {
  return (
    <section className="features" id="features" aria-labelledby="features-title">
      <div className="wrap">
        <h2 className="features-title" id="features-title">
          <span>One keyboard.</span> <span>All your apps.</span>
        </h2>

        <div className="feat-grid">
          <article className="feat">
            <div className="feat-visual" aria-hidden>
              <div className="feat-keys">
                {BOUND.map((b) => (
                  <span className="feat-bound" key={b.key}>
                    <span className="feat-key">
                      {b.key}
                      <span className="feat-keydot" />
                    </span>
                    <small>{b.label}</small>
                  </span>
                ))}
              </div>
            </div>
            <h3>Bind any action to any key.</h3>
          </article>

          <article className="feat">
            <div className="feat-visual" aria-hidden>
              <div className="feat-strip">
                <GlyfKey />
                {TOOLS.map((t) => (
                  <span className="feat-tool" key={t.label} title={t.label}>
                    {t.icon}
                  </span>
                ))}
              </div>
            </div>
            <h3>AI and all your apps, inside the keyboard.</h3>
          </article>

          <article className="feat">
            <div className="feat-visual" aria-hidden>
              <div className="feat-answers">
                {ANSWERS.map((a) => (
                  <span className="feat-answer" key={a.text}>
                    <span className="feat-answer-icon">{a.icon}</span>
                    <b>{a.text}</b>
                    <span>{a.meta}</span>
                  </span>
                ))}
              </div>
            </div>
            <h3>Skip the trips between apps.</h3>
          </article>
        </div>

        <div className="works">
          <h3 className="works-title">Works with</h3>
          <ul className="works-list">
            {WORKS_WITH.map((w) => (
              <li key={w.name}>
                <span className="works-icon" aria-hidden>
                  {w.icon}
                </span>
                {w.name}
              </li>
            ))}
          </ul>
        </div>

        <p className="try-cue">Try it here.</p>
      </div>
    </section>
  );
}
