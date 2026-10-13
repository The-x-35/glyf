import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import Wordmark from "../../components/Wordmark";

export const metadata: Metadata = {
  title: "Privacy Policy · Glyf",
  description: "What the Glyf keyboard and app collect, what stays on your phone, and how to delete your account.",
  alternates: { canonical: "/privacy" },
};

const UPDATED = "14 October 2026";
const EMAIL = "arpit@tryglyf.com";

export default function Privacy() {
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
          <h1>Privacy Policy</h1>
          <p className="legal-date">Effective {UPDATED}</p>

          <p>
            Glyf is a keyboard for iPhone and Android, with an app that sets it up. It is made by Arpit Singh
            (&ldquo;Glyf&rdquo;, &ldquo;we&rdquo;). This page says what Glyf collects, why, who else handles it,
            and how to delete it. Questions: <a href={`mailto:${EMAIL}`}>{EMAIL}</a>.
          </p>

          <h2>The short version</h2>
          <ul>
            <li>What you type stays on your phone unless you use a feature that needs our server: AI features, search and translation, and AI suggestions as you type if you agree to them.</li>
            <li>We don&rsquo;t keep the text you send, unless you share it as a page. Our server logs that something ran and how long it took, never your words.</li>
            <li>Your saved details, notes, clipboard, contacts, calendar and learned words stay on your phone.</li>
            <li>We don&rsquo;t sell your data, show ads, or track you across other apps.</li>
            <li>
              Google data (from Sign in with Google, Google Calendar and Google Meet) is used only for those features,
              is never sent to an AI model, and is never used to train one.
            </li>
            <li>AI requests go only to providers that don&rsquo;t keep or train on what they are sent.</li>
            <li>You can have your account and its data deleted at any time.</li>
          </ul>

          <h2>What stays on your phone</h2>
          <p>These are kept on your device and never sent to us:</p>
          <ul>
            <li>Your vault: the details you save, such as your address or payment ID, encrypted on the device.</li>
            <li>Notes, shorthand, and the words the keyboard learns from your typing.</li>
            <li>Clipboard history, and the screenshots from the last two days it shows (with the photo permission).</li>
            <li>Contacts, when you let the keyboard search them.</li>
            <li>Your calendar, when you let the keyboard show it and add events to it.</li>
            <li>Dictation, which is turned into text on the device.</li>
            <li>Keyboard settings and game scores.</li>
          </ul>

          <h2>What the keyboard sends, and when</h2>
          <p>
            On iPhone a keyboard reaches the internet only with Full Access; on Android it can by default. Glyf uses
            it only for the features below; everything else you type stays on your phone. The app shows this list on a
            &ldquo;What Glyf sends&rdquo; screen before the keyboard is turned on, and nothing marked &ldquo;only if
            you agree&rdquo; is sent until you do.
          </p>
          <ul>
            <li>
              <strong>AI features you start.</strong> When you hold the space bar, tap Rewrite, ask Glyf, hold a
              Glyf key or translate, the text involved goes to our server and to an AI model to produce the result.
            </li>
            <li>
              <strong>AI suggestions as you type, only if you agree.</strong> When you pause while typing, the
              sentence you are typing (up to its last 120 characters) is sent to suggest one action, such as
              &ldquo;Tidy this up&rdquo;. It is sent with the kinds of details in your vault (for example
              &ldquo;address&rdquo;), never the details themselves. Never from password fields, and on Android never
              from a field that asks for no learning, such as an incognito tab. Turn it on or off in the Glyf app under
              Profile, Keyboard, AI suggestions as you type.
            </li>
            <li>
              <strong>Your saved details, only if you agree.</strong> With &ldquo;Let AI use your saved
              details&rdquo; on, each AI request you start carries the details you saved (your name, email, phone
              number, address, payment ID, links, social handles, company and bio) so an answer like &ldquo;send them
              my address&rdquo; can fill them in. Turn it off under Profile, Keyboard.
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
          <p>
            Another: when you report an AI result with the flag beside it, we keep that result, what kind of request
            made it, your account and your phone&rsquo;s random ID, so we can look into it and fix what went wrong.
          </p>

          <h2>Your account</h2>
          <p>
            You sign in with Apple or Google. We receive and keep your account ID from Apple or Google, your email,
            your name if you share it, how you signed in, your phone&rsquo;s platform, app version, language, region
            and time zone, and when you joined and were last seen. We also keep your plan, the keyboard settings that
            aren&rsquo;t private, the kinds of details in your vault and how many notes and shortcuts you have (never
            their contents), and app activity such as which screens you open and which setup steps are done (the
            keyboard added, opened, given Full Access, first used), as names and counts, never text. We
            use this only to run your account, keep daily limits fair, and improve Glyf&rsquo;s features.
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
              <strong>AI providers.</strong> The text you choose to run an AI feature on, and with Suggestions on the
              sentence you are typing, is sent through OpenRouter to the model that answers: Qwen, Ling or Gemini,
              served by providers such as Alibaba Cloud, Novita and Google. Every request tells OpenRouter to use only
              providers that don&rsquo;t keep or train on what they are sent, and Glyf uses no free AI tiers. They
              process it only to return the result to you. No Google user data is ever sent to an AI provider.
            </li>
            <li>
              <strong>Search and maps.</strong> Your search goes to providers such as Google (Places and YouTube),
              Geoapify and Wikipedia to find results.
            </li>
            <li>
              <strong>GIFs and stickers.</strong> Searches in the emoji board go from your phone straight to KLIPY,
              with a random ID of their own so KLIPY can show the GIFs you used recently.
            </li>
            <li>
              <strong>Booking.</strong> When you book a time on someone&rsquo;s Cal.com page, the name, email and
              guests you enter are sent to Cal.com through our server, and Cal.com emails the invitations.
            </li>
            <li>
              <strong>Google Calendar and Meet.</strong> If you connect Google, the keyboard adds events to your
              Google Calendar and makes Meet links directly from your phone; see{" "}
              <a href="#google-user-data">Google user data</a> below.
            </li>
            <li>
              <strong>Temporary email.</strong> A throwaway address comes from mail.tm, which your phone reaches
              directly: it receives only the address and password Glyf made up for it, and the inbox is read onto your
              phone.
            </li>
            <li>
              <strong>Prices.</strong> A cashtag such as $SOL, or a wallet address you copy, is looked up for its price
              through our server, which asks Jupiter. Exchange rates for money in the strip are the European Central
              Bank&rsquo;s, which your phone fetches from Frankfurter (our server only if that fails), with nothing of
              yours attached.
            </li>
            <li>
              <strong>Weather.</strong> When you ask the strip about the weather (&ldquo;will it rain tomorrow&rdquo;),
              your phone sends your approximate location, rounded to about a kilometre, straight to Open-Meteo for the
              forecast. Nothing else goes with it, and it doesn&rsquo;t pass through our server. Sunrise and sunset are
              worked out on your phone.
            </li>
            <li>
              <strong>Wallet.</strong> If you use Glyf&rsquo;s wallet, signing is handled by the wallet app you choose, such as
              Phantom; Glyf never holds your keys. Transactions you sign go to the Solana network through our server,
              which passes them on without storing or logging them; swaps you start go from your phone to Jupiter, and
              private sends to MagicBlock. Blockchain transactions are public by nature.
            </li>
            <li>
              <strong>Hosting.</strong> Our server runs on Railway, our database on Neon, and this website on
              Vercel.
            </li>
          </ul>
          <p>We share data with these services only to provide the feature you are using.</p>

          <h2 id="google-user-data">Google user data</h2>
          <p>Glyf asks Google for access only when you turn on a feature that needs it:</p>
          <ul>
            <li>
              <strong>Sign in with Google:</strong> your Google account ID, name and email address, to create your
              Glyf account and sign you in.
            </li>
            <li>
              <strong>Google Calendar</strong> (permission to see, create, change and delete events on calendars you
              own): to add the events you create in the keyboard to your Google Calendar, invite the guests you name,
              and change or delete those events when you ask.
            </li>
            <li>
              <strong>Google Meet</strong> (permission to create Meet conferences): to make a Meet link when you ask
              for one, for an event or for a message.
            </li>
          </ul>
          <p>How Glyf handles it:</p>
          <ul>
            <li>
              Calendar and Meet requests go straight from your phone to Google, and the access Google grants is stored
              only on your phone. Glyf&rsquo;s servers never receive your calendar events or your Meet details.
            </li>
            <li>
              Glyf uses Google user data only to provide and improve these features for you. It is not used for
              advertising, it is not sold, and it is not used to build a profile of you.
            </li>
            <li>
              Glyf never sends Google user data to any AI model or AI provider, and never uses it, raw, aggregated or
              derived, to develop, improve or train AI or machine-learning models.
            </li>
            <li>
              Glyf does not transfer Google user data to anyone, except as part of a feature you ask for (such as an
              event&rsquo;s details put into your message) or where the law requires it. No person reads it.
            </li>
            <li>
              You can turn Calendar or Meet off at any time in the Glyf app under Profile, Connected tools, and
              remove Glyf&rsquo;s access at{" "}
              <a href="https://myaccount.google.com/permissions">myaccount.google.com/permissions</a>.
            </li>
          </ul>
          <p>
            Glyf&rsquo;s use and transfer to any other app of information received from Google APIs will adhere to
            the{" "}
            <a href="https://developers.google.com/terms/api-services-user-data-policy">
              Google API Services User Data Policy
            </a>
            , including the Limited Use requirements. The use of raw or derived user data received from Google
            Workspace APIs will adhere to the{" "}
            <a href="https://developers.google.com/workspace/workspace-api-user-data-developer-policy">
              Google Workspace API User Data and Developer Policy
            </a>
            , including the Limited Use requirements.
          </p>

          <h2>The waitlist</h2>
          <p>
            If you join the waitlist on this website, we keep your email and where you signed up, to tell you when
            Glyf launches. Email us to be removed.
          </p>

          <h2 id="delete">Deleting your account and data</h2>
          <p>
            Email <a href={`mailto:${EMAIL}`}>{EMAIL}</a> from the address on your account and we will delete your
            account, its settings and its activity from our server within 30 days, or send you a copy. What is stored
            on your phone stays until you delete the app.
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
          <Wordmark href="/" label="Glyf home" />
          <p className="footer-legal">© 2026 Glyf · iPhone and Android</p>
        </div>
      </footer>
    </>
  );
}
