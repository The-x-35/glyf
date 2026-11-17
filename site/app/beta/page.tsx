import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import Wordmark from "../../components/Wordmark";

export const metadata: Metadata = {
  title: "Test Glyf on Android · Glyf",
  description: "Join the Glyf beta on Google Play: three taps, then the AI keyboard is on your Android phone.",
  alternates: { canonical: "/beta" },
};

const GROUP = "https://groups.google.com/g/glyf-beta";
const OPT_IN = "https://play.google.com/apps/testing/com.arpit.glyf";
const LISTING = "https://play.google.com/store/apps/details?id=com.arpit.glyf";
const EMAIL = "arpit.k3note@gmail.com";

// Google Play lets members of the glyf-beta Google Group into the closed
// test, so joining the group is the whole sign-up. Play also wants 12+
// testers who stay in for 14 days before the app can go public.
export default function Beta() {
  return (
    <>
      <header className="nav">
        <div className="wrap nav-inner">
          <Wordmark href="/" label="Glyf home" />
          <div className="nav-end">
            <ThemeToggle />
          </div>
        </div>
      </header>

      <main className="legal">
        <div className="legal-inner">
          <h1>Test Glyf on Android</h1>
          <p>
            Glyf is an AI keyboard: hold space to rewrite, answer or translate what you typed, right where you type.
            It&rsquo;s in testing on Google Play. Use the Google account that&rsquo;s on your Android phone for every
            step.
          </p>
          <ol>
            <li>
              <a href={GROUP}>Join the Glyf Beta group</a> and tap <strong>Join group</strong>. No emails come from
              it.
            </li>
            <li>
              <a href={OPT_IN}>Become a tester</a> and tap <strong>Become a tester</strong>.
            </li>
            <li>
              <a href={LISTING}>Install Glyf from Google Play</a>, open it and follow the steps to turn the keyboard
              on.
            </li>
          </ol>

          <h2>One favour</h2>
          <p>
            Keep Glyf installed and stay in the test for 14 days. Google needs that before Glyf can go public for
            everyone.
          </p>

          <h2>Something broke?</h2>
          <p>
            Tap the flag beside any AI result, or email <a href={`mailto:${EMAIL}?subject=Glyf%20beta`}>{EMAIL}</a>.
          </p>
        </div>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <Wordmark href="/" label="Glyf home" />
          <p className="footer-legal">© 2026 Glyf · iPhone and Android · <a href="/terms">Terms</a></p>
        </div>
      </footer>
    </>
  );
}
