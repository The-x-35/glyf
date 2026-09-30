import Experience from "@/components/chat/Experience";
import Cursor from "@/components/Cursor";
import BackdropKeys from "@/components/BackdropKeys";
import Features from "@/components/Features";
import ThemeToggle from "@/components/ThemeToggle";
import Waitlist from "@/components/Waitlist";
import Wordmark from "../components/Wordmark";

// BRAND-REVIEW (2026-09-30): hidden while Google reviews Glyf's sign-in branding; restore after it passes:
// the Apple and Google Play marks, and store badges for apps not in the stores yet.
// const AppleMark = () => (
//   <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden>
//     <path d="M17.05 12.53c-.03-2.9 2.37-4.29 2.48-4.36-1.35-1.97-3.45-2.24-4.2-2.27-1.79-.18-3.49 1.05-4.4 1.05-.9 0-2.3-1.02-3.79-1-1.95.03-3.74 1.13-4.74 2.87-2.02 3.5-.52 8.68 1.45 11.52.96 1.39 2.11 2.95 3.62 2.9 1.45-.06 2-.94 3.76-.94s2.25.94 3.79.91c1.56-.03 2.55-1.42 3.51-2.82 1.1-1.62 1.56-3.19 1.58-3.27-.03-.02-3.03-1.16-3.06-4.59zM14.16 4c.8-.97 1.34-2.32 1.19-3.66-1.15.05-2.55.77-3.38 1.73-.74.86-1.39 2.23-1.22 3.55 1.29.1 2.6-.65 3.41-1.62z" />
//   </svg>
// );
//
// const PlayMark = () => (
//   <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor" aria-hidden>
//     <path d="M3.6 1.8c-.36.38-.6.97-.6 1.73v16.94c0 .76.24 1.35.6 1.73l.1.09 9.49-9.49v-.22L3.7 1.71l-.1.09z" />
//     <path d="M16.35 15.95l-3.16-3.16v-.22l3.16-3.16.07.04 3.75 2.13c1.07.6 1.07 1.6 0 2.21l-3.75 2.12-.07.04z" opacity=".75" />
//     <path d="M16.42 15.9L13.19 12.7 3.6 22.2c.35.37.93.42 1.59.05l11.23-6.35z" opacity=".55" />
//     <path d="M16.42 8.1L5.19 1.75C4.53 1.38 3.95 1.43 3.6 1.8l9.59 9.5 3.23-3.2z" opacity=".9" />
//   </svg>
// );
//
// /** Greyed out on purpose: the apps aren't in the stores yet. */
// const StoreBadges = () => (
//   <div className="stores" aria-label="Coming soon to the App Store and Google Play">
//     <span className="store" aria-disabled="true">
//       <AppleMark />
//       <span className="store-lines">
//         <small>Coming soon on</small>
//         <b>App Store</b>
//       </span>
//     </span>
//     <span className="store" aria-disabled="true">
//       <PlayMark />
//       <span className="store-lines">
//         <small>Coming soon on</small>
//         <b>Google Play</b>
//       </span>
//     </span>
//   </div>
// );

/** Coming soon, in words: the same pills without any store's mark. */
const StoreBadges = () => (
  <div className="stores" aria-label="Coming soon to iPhone and Android">
    <span className="store" aria-disabled="true">
      <span className="store-lines">
        <small>Coming soon on</small>
        <b>iPhone</b>
      </span>
    </span>
    <span className="store" aria-disabled="true">
      <span className="store-lines">
        <small>Coming soon on</small>
        <b>Android</b>
      </span>
    </span>
  </div>
);

export default function Page() {
  return (
    <>
      <Cursor />
      <BackdropKeys />

      <header className="nav">
        <div className="wrap nav-inner">
          <Wordmark href="#top" label="Glyf home" />
          <div className="nav-end">
            <ThemeToggle />
            <a className="nav-cta" href="#join">Join waitlist</a>
          </div>
        </div>
      </header>

      <main>
        <section className="hero" id="top">
          <div className="wrap hero-copy">
            <h1 className="hero-title">
              <span>Type less.</span>{" "}
              <span>
                <span className="hero-mark hero-logo">
                  <img className="wordmark-light" src="/brand/glyf-wordmark-light.svg" alt="glyf" width={1924} height={1131} />
                  <img className="wordmark-dark" src="/brand/glyf-wordmark-dark.svg" alt="" aria-hidden="true" width={1924} height={1131} />
                </span>{" "}
                more.
              </span>
            </h1>
            <p className="hero-sub">The AI keyboard that does the rest.</p>
            <StoreBadges />
            <div className="hero-form">
              <Waitlist source="hero" />
            </div>
          </div>
        </section>

        <Features />

        <div id="try">
          <Experience />
        </div>

        <section className="finale" id="join">
          <div className="wrap">
            <h2 className="display">Made for your thumbs.</h2>
            <div className="finale-form">
              <Waitlist source="footer" />
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <Wordmark href="#top" label="Glyf home" />
          <p className="footer-legal">© 2026 Glyf · iPhone and Android · <a href="/privacy">Privacy</a></p>
          <p className="footer-tm">
            Android is a trademark of Google LLC. iPhone is a trademark of Apple Inc. Glyf is not affiliated with or
            endorsed by Google or Apple.
          </p>
        </div>
      </footer>
    </>
  );
}
