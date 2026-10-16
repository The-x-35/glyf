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
            <li>
              Email <a href={`mailto:${EMAIL}?subject=Delete%20my%20Glyf%20account`}>{EMAIL}</a> from the address on
              your Glyf account (the one from Sign in with Apple or Google), with the subject &ldquo;Delete my Glyf
              account&rdquo;.
            </li>
            <li>We reply to confirm, and delete the account within 30 days.</li>
          </ol>

          <h2>What is deleted</h2>
          <ul>
            <li>
              Your account: the Apple or Google account ID, email and name, how you signed in, your phone&rsquo;s
              platform, app version, language, region and time zone, and when you joined and were last seen.
            </li>
            <li>The keyboard settings and the app activity (names and counts, never text) kept with it.</li>
            <li>AI results you reported with the flag in the keyboard.</li>
          </ul>

          <h2>What is kept</h2>
          <ul>
            <li>
              Records of App Store purchases, which tie a subscription to the account that bought it so a receipt
              can&rsquo;t be reused. Deleting your account doesn&rsquo;t cancel a subscription: cancel it in your Apple
              ID&rsquo;s subscriptions.
            </li>
            <li>
              Glyfs you built and published, and place lists you shared as a page, which aren&rsquo;t tied to your
              account. Ask in the same email and we delete those too.
            </li>
          </ul>

          <h2>On your phone</h2>
          <p>
            Your saved details, notes, clipboard and learned words never reach our server. They stay on your phone
            until you delete the Glyf app.
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
