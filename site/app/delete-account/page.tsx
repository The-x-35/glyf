import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import Wordmark from "../../components/Wordmark";

export const metadata: Metadata = {
  title: "Delete your account · Glyf",
  description: "How to delete your Glyf account and what is deleted.",
  alternates: { canonical: "/delete-account" },
};

const EMAIL = "arpit@tryglyf.com";

// Google Play asks for a web page that names the app, gives the steps and
// says what is deleted and what is kept (Data safety, account deletion).
export default function DeleteAccount() {
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
          <h1>Delete your Glyf account</h1>
          <p>
            For Glyf: AI Keyboard on iPhone and Android, made by Arpit Singh. To delete your account and what our
            server keeps about it:
          </p>
          <ol>
            <li>In the Glyf app, open Profile and tap Delete account at the bottom.</li>
            <li>Confirm. The account is deleted at once, and the app erases what it keeps on your phone.</li>
          </ol>
          <p>
            No longer have the app? Email <a href={`mailto:${EMAIL}?subject=Delete%20my%20Glyf%20account`}>{EMAIL}</a>{" "}
            from the address on your Glyf account (the one from Sign in with Apple or Google), with the subject
            &ldquo;Delete my Glyf account&rdquo;, and we delete it within 30 days.
          </p>

          <h2>What is deleted</h2>
          <ul>
            <li>
              Your account: the Apple or Google account ID, email and name, how you signed in, your phone&rsquo;s
              platform, app version, language, region and time zone, and when you joined and were last seen.
            </li>
            <li>The keyboard settings and the app activity (names and counts, never text) kept with it.</li>
            <li>Your purchase records, usage counts and AI results you reported with the flag in the keyboard.</li>
            <li>Glyfs you built or published, place lists you shared as a page, and connected tools.</li>
          </ul>

          <h2>What is kept</h2>
          <ul>
            <li>
              Daily totals that name no one (how many people opened the app on a day). Deleting your account
              doesn&rsquo;t cancel a subscription: cancel it in your Apple ID&rsquo;s or Google Play&rsquo;s
              subscriptions.
            </li>
          </ul>

          <h2>On your phone</h2>
          <p>
            Your saved details, notes, clipboard and learned words never reach our server. Delete account in the
            app erases them from your phone too; otherwise they stay until you delete the Glyf app.
          </p>
          <p>
            More in the <a href="/privacy">privacy policy</a>.
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
