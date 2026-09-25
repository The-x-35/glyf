import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";

export const metadata: Metadata = {
  title: "Privacy Policy · Glyf",
  description: "What the Glyf keyboard and app collect, what stays on your phone, and how to delete your account.",
  alternates: { canonical: "/privacy" },
};

const UPDATED = "25 September 2026";
const EMAIL = "arpit@tryglyf.com";

export default function Privacy() {
  return (
    <>
      <header className="nav">
        <div className="wrap nav-inner">
          <a className="wordmark" href="/" aria-label="Glyf home">
            glyf<span className="dot" />
          </a>
          <div className="nav-end">
            <ThemeToggle />
          </div>
        </div>
      </header>

      <main className="legal">
        <div className="legal-inner">
          <h1>Privacy Policy</h1>
          <p className="legal-date">Effective {UPDATED}</p>

          <p>
            Glyf is a keyboard for iPhone and Android, with an app that sets it up. It is made by Arpit Singh
            (&ldquo;Glyf&rdquo;, &ldquo;we&rdquo;). This page says what Glyf collects, why, who else handles it,
            and how to delete it. Questions: <a href={`mailto:${EMAIL}`}>{EMAIL}</a>.
          </p>

          <h2>The short version</h2>
          <ul>
            <li>What you type stays on your phone unless you use a feature that needs our server: AI features, suggestions, search and translation.</li>
            <li>We don&rsquo;t keep the text you send, unless you share it as a page. Our server logs that something ran and how long it took, never your words.</li>
            <li>Your saved details, notes, clipboard, contacts, calendar and learned words stay on your phone.</li>
            <li>We don&rsquo;t sell your data, show ads, or track you across other apps.</li>
            <li>You can delete your account in the app at any time.</li>
          </ul>

          <h2>What stays on your phone</h2>
          <p>These are kept on your device and never sent to us:</p>
          <ul>
            <li>Your vault: the details you save, such as your address or payment ID, encrypted on the device.</li>
            <li>Notes, shorthand, and the words the keyboard learns from your typing.</li>
            <li>Clipboard history, and the screenshots from the last hour it shows (with the photo permission).</li>
            <li>Contacts, when you let the keyboard search them.</li>
            <li>Your calendar, when you let the keyboard show it and add events to it.</li>
            <li>Dictation, which is turned into text on the device.</li>
            <li>Keyboard settings and game scores.</li>
          </ul>

          <h2>What the keyboard sends, and when</h2>
          <p>
            A keyboard with Full Access can reach the internet. Glyf uses that only for the features below;
            everything else you type stays on your phone.
          </p>
          <ul>
            <li>
              <strong>AI features you start.</strong> When you hold the space bar, tap Rewrite, ask Glyf, hold a
              Glyf key or translate, the text involved goes to our server and to an AI model to produce the result.
            </li>
            <li>
              <strong>Suggestions.</strong> With Full Access and Suggestions on, when you pause while typing, the
              sentence you are typing is sent to suggest one action, such as &ldquo;Tidy this up&rdquo;. It is sent
              with the kinds of details in your vault (for example &ldquo;address&rdquo;), never the details
              themselves. Turn this off in the Glyf app under Profile, Keyboard, Suggestions.
            </li>
            <li>
              <strong>Your saved details.</strong> With &ldquo;Let AI use your saved details&rdquo; on (the default),
              a request that asks for one of your details, like &ldquo;send them my address&rdquo;, can include your
              name, email, phone number, address, payment ID or links so the answer can fill them in. Turn it off
              under Profile, Keyboard.
            </li>
            <li>
              <strong>Search.</strong> What you search in the keyboard&rsquo;s Search, YouTube and Maps tabs goes to
              our server and our search providers to find results.
            </li>
            <li>
              <strong>Location.</strong> With Nearby search on, your approximate location (to about a kilometre) is
              kept on your phone and sent with searches that need it, like &ldquo;coffee near me&rdquo; or the
              weather. We don&rsquo;t store it.
            </li>
          </ul>
          <p>
            Before any text reaches an AI model, card numbers, one-time codes, passwords and keys in it are replaced
            with placeholders, and put back only in the answer you see. Results may be held in memory for up to a
            day so the same request isn&rsquo;t run twice; they are never written to a database.
          </p>
          <p>
            One exception: when you hold the space bar on a search for places and send the list, Glyf saves it as a
            page with a link, holding the words you typed as its title and the places found. Anyone with the link
            can open it.
          </p>

          <h2>Your account</h2>
          <p>
            You sign in with Apple or Google. We receive and keep your account ID from Apple or Google, your email,
            your name if you share it, how you signed in, your phone&rsquo;s platform, app version, language, region
            and time zone, and when you joined and were last seen. We also keep your plan, the keyboard settings that
            aren&rsquo;t private, the kinds of details in your vault and how many notes and shortcuts you have (never
            their contents), and app activity such as which screens you open, as names and counts, never text. We
            use this to run your account, keep daily limits fair, and improve Glyf.
          </p>
          <p>
            Your phone also has a random ID, used to count requests when you are signed out and to keep the Glyfs
            you build. Glyfs you build are saved on our server; the ones you publish can be seen and added by
            others.
          </p>
          <p>
            To stop one person using up the service, we count requests per account, or per phone when signed out,
            for a day. Those counts are deleted after two days.
          </p>

          <h2>Who else handles your data</h2>
          <ul>
            <li>
              <strong>AI providers.</strong> AI requests are processed by OpenRouter and the model providers it
              connects to (such as Google, Mistral, Meta through Groq, and Alibaba&rsquo;s Qwen), and by
              Google&rsquo;s Gemini API. Suggestions only go to providers that don&rsquo;t store or train on what
              they are sent. Other requests are handled under each provider&rsquo;s own terms; content sent to
              Google&rsquo;s Gemini API on its unpaid tier can be used by Google to improve its services.
            </li>
            <li>
              <strong>Search and maps.</strong> Your search goes to providers such as Google (Places and YouTube),
              Geoapify and Wikipedia to find results.
            </li>
            <li>
              <strong>GIFs and stickers.</strong> Searches in the emoji board go from your phone straight to KLIPY.
            </li>
            <li>
              <strong>Booking.</strong> When you book a time on someone&rsquo;s Cal.com page, the name, email and
              guests you enter are sent to Cal.com through our server, and Cal.com emails the invitations.
            </li>
            <li>
              <strong>Google Calendar and Meet.</strong> If you connect Google, the keyboard adds events to your
              Google Calendar and makes Meet links directly from your phone. The access stays on your phone; we never
              see your calendar.
            </li>
            <li>
              <strong>Wallet.</strong> If you use Glyf&rsquo;s wallet, sign-in and signing are handled by Privy or
              the wallet app you choose. Blockchain transactions are public by nature.
            </li>
            <li>
              <strong>Hosting.</strong> Our server runs on Railway, our database on Neon, and this website on
              Vercel.
            </li>
          </ul>
          <p>We share data with these services only to provide the feature you are using.</p>

          <h2>The waitlist</h2>
          <p>
            If you join the waitlist on this website, we keep your email and where you signed up, to tell you when
            Glyf launches. Email us to be removed.
          </p>

          <h2>Deleting your data</h2>
          <p>
            In the Glyf app, go to Profile and tap Delete account. That deletes your account, its settings and its
            activity from our server. What is stored on your phone stays until you delete the app. You can also email
            us to delete your data or get a copy of it.
          </p>

          <h2>Children</h2>
          <p>
            Glyf is not meant for children under 13, and we don&rsquo;t knowingly collect their data. If you think
            a child has given us data, email us and we will delete it.
          </p>

          <h2>Security</h2>
          <p>
            Everything Glyf sends travels over encrypted connections, your vault is encrypted on your device, and
            sessions are signed so only you can use them. No system is perfectly secure, but we keep what we hold to
            the minimum.
          </p>

          <h2>Your rights</h2>
          <p>
            Depending on where you live, you may have the right to see, correct, delete or take a copy of your data,
            and to object to how it is used. Email <a href={`mailto:${EMAIL}`}>{EMAIL}</a> and we will answer within
            30 days.
          </p>

          <h2>Changes</h2>
          <p>
            If this policy changes, we will update this page and the date at the top, and tell you in the app when
            the change matters.
          </p>
        </div>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <a className="wordmark" href="/" aria-label="Glyf home">
            glyf<span className="dot" />
          </a>
          <p className="footer-legal">© 2026 Glyf · iPhone and Android</p>
        </div>
      </footer>
    </>
  );
}
