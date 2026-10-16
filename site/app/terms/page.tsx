import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import Wordmark from "../../components/Wordmark";

export const metadata: Metadata = {
  title: "Terms of Service · Glyf",
  description: "The terms for using the Glyf keyboard and app: accounts, plans, the wallet, AI results and your rights.",
  alternates: { canonical: "/terms" },
};

const EFFECTIVE = "17 October 2026";
const EMAIL = "arpit@tryglyf.com";

export default function Terms() {
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
          <h1>Terms of Service</h1>
          <p className="legal-date">Effective {EFFECTIVE}</p>

          <p>
            Glyf is a keyboard for iPhone and Android, with an app that sets it up. It is made by Arpit Singh
            (&ldquo;Glyf&rdquo;, &ldquo;we&rdquo;, &ldquo;us&rdquo;). These terms are the agreement between you and
            us when you use the Glyf keyboard, the Glyf app, our server and this website. By using Glyf you agree to
            them. If you don&rsquo;t agree, please don&rsquo;t use Glyf. How we handle your data is in the{" "}
            <a href="/privacy">privacy policy</a>. Questions: <a href={`mailto:${EMAIL}`}>{EMAIL}</a>.
          </p>

          <h2>The short version</h2>
          <ul>
            <li>Use Glyf for yourself and within the law, and don&rsquo;t try to break or overload it.</li>
            <li>The free plan gives you 50 AI runs a week. Plus and Max give you more.</li>
            <li>Store plans are billed and refunded by Apple or Google. Plans paid in USDC are prepaid and don&rsquo;t renew.</li>
            <li>AI results can be wrong. Check them before you send or rely on them.</li>
            <li>Glyf never holds your crypto keys or funds. Blockchain transactions can&rsquo;t be undone. Nothing in Glyf is financial advice.</li>
            <li>Glyf is offered as it is, by one person, and our liability is limited.</li>
          </ul>

          <h2>Who can use Glyf</h2>
          <p>
            You must be at least 13 to use Glyf. To pay for a plan or use the wallet, you must be old enough to make a
            binding agreement where you live, which is 18 in most places. If you use Glyf for an organisation, you
            confirm you may accept these terms for it.
          </p>

          <h2>Your account</h2>
          <p>
            You sign in with Apple or Google. Keep that account secure: what happens under your Glyf account is your
            responsibility. Tell us at <a href={`mailto:${EMAIL}`}>{EMAIL}</a> if you think someone else is using it.
            You can delete your account at any time, as described on the{" "}
            <a href="/delete-account">delete your account</a> page.
          </p>

          <h2>The free plan</h2>
          <p>
            The free plan includes 50 AI runs a week. An AI run is one AI feature you start, such as a rewrite, an
            answer or a Glyf you hold. Typing, autocorrect, suggestions as you type, the vault, the clipboard and the
            features that work on your phone don&rsquo;t use runs. Unused runs don&rsquo;t carry over. We may change what
            the free plan includes, and we will say so in the app before a change that takes something away.
          </p>

          <h2>Plus and Max</h2>
          <p>
            Plus and Max are paid plans that give you more AI runs and features, at the prices shown in the app
            before you pay. Which plan you have is kept on your Glyf account, so it works on every phone where you
            sign in with that account.
          </p>
          <ul>
            <li>
              <strong>Through the App Store or Google Play.</strong> Apple or Google takes the payment, under their
              own terms. These plans renew automatically until you cancel them in your Apple or Google account
              settings, and cancelling stops the next renewal. Refunds are handled by Apple or Google under their
              policies, so ask them.
            </li>
            <li>
              <strong>In USDC, in the Solana dApp Store version.</strong> You pay from your own wallet for a fixed
              period, one month (30 days) or one year (365 days). It is prepaid and does not renew: when the period
              ends, the plan ends unless you pay again. Glyf is the seller for these payments, not Solana Mobile. A
              plan starts once the payment is confirmed on Solana. You pay the network fee, and you are responsible
              for sending the exact amount to the address the app shows. A payment can&rsquo;t be reversed on the
              blockchain, so refunds are made by us: email <a href={`mailto:${EMAIL}`}>{EMAIL}</a> within 14 days
              of paying with the transaction, and we refund in USDC to the wallet that paid, shortening the plan to
              match. Where the law gives you more rights to a refund, you keep them.
            </li>
            <li>
              <strong>Gift codes.</strong> A code we hand out adds the plan and period it names to your account. It
              can be used once, has no cash value and can&rsquo;t be exchanged for money.
            </li>
          </ul>
          <p>
            Prices can change. A change applies from your next renewal or your next payment, never to a period you
            have already paid for. Prices may or may not include taxes, depending on the store and where you live.
          </p>

          <h2>Acceptable use</h2>
          <p>Please don&rsquo;t use Glyf to:</p>
          <ul>
            <li>break the law, or help someone else break it;</li>
            <li>harass, threaten, defraud or impersonate anyone, or spread hate, spam or malware;</li>
            <li>make content that sexualises minors, or that you have no right to share;</li>
            <li>
              get around plan limits, share an account to do so, or reach our server other than through the Glyf
              apps;
            </li>
            <li>
              copy, take apart or overload Glyf or the services it uses, or probe them for weaknesses without our
              written permission (we welcome security reports at <a href={`mailto:${EMAIL}`}>{EMAIL}</a>);
            </li>
            <li>publish Glyfs or pages that break these rules.</li>
          </ul>
          <p>
            You are responsible for what you write, send and publish with Glyf. You keep the rights to it. You give us
            only the permission needed to run the features you use, such as processing your text to return an AI
            result, or showing a page or a Glyf you chose to publish to the people who open it.
          </p>

          <h2>AI results</h2>
          <p>
            Glyf&rsquo;s AI features are produced by AI models and can be wrong, out of date, incomplete or
            inappropriate, even when they sound sure. They are not professional advice, whether medical, legal,
            financial or any other kind. Read a result before you send it or act on it; what you send is yours. If a
            result is harmful or wrong, report it with the flag beside it.
          </p>

          <h2>The wallet</h2>
          <p>
            The wallet is an optional feature you turn on in the app&rsquo;s settings. It lets you send tokens and
            buy them from the keyboard.
          </p>
          <ul>
            <li>
              <strong>Glyf never holds your keys or your funds.</strong> Every transaction is signed in the wallet
              app you choose, such as Phantom, Solflare or Seed Vault Wallet, and only there. Keep your wallet and
              its recovery phrase safe; we can&rsquo;t recover them.
            </li>
            <li>
              <strong>Swaps go through Jupiter.</strong> When you buy a token, the swap is priced and carried out by
              Jupiter, a third-party exchange, under its terms. The price can move between the quote and the swap.
              Glyf may add a fee of 0.5% of the swap, which is included in the amount you see before you sign.
            </li>
            <li>
              <strong>Blockchain transactions are final.</strong> Once a transaction is signed and sent, it
              can&rsquo;t be cancelled or reversed, by you or by us. Check the address, the token and the amount
              before you sign. Network fees are yours to pay.
            </li>
            <li>
              <strong>No financial advice.</strong> Prices, token names and anything else Glyf shows are for
              information only. Glyf does not recommend buying, selling or holding anything. Tokens are risky and can
              lose all their value. Some tokens, including tokenized stocks, may not be offered where you live, and
              some versions of Glyf don&rsquo;t offer them.
            </li>
            <li>
              You are responsible for the taxes on your transactions and for following the laws where you live.
            </li>
          </ul>

          <h2>Other services</h2>
          <p>
            Some features rely on services run by others, such as Apple and Google (sign-in, Calendar, Meet and the
            app stores), our AI and search providers, KLIPY, Cal.com, mail.tm, Jupiter, MagicBlock, wallet apps and
            the Solana network. Their terms apply when you use them, they can change or stop, and we aren&rsquo;t
            responsible for them. The privacy policy lists what each one receives.
          </p>

          <h2>Glyf itself</h2>
          <p>
            Glyf, its name, design and code belong to us. We give you a personal, non-transferable licence to use the
            Glyf apps on your devices under these terms. We work to keep Glyf running and improving, but features can
            change, and Glyf, or parts of it, can be unavailable at times.
          </p>

          <h2>Ending your use</h2>
          <p>
            You can stop using Glyf and delete your account at any time. We may suspend or close an account that
            breaks these terms or puts Glyf or others at risk, and will tell you why unless the law or safety stops
            us. If we stop offering Glyf altogether, we will tell you ahead of time and refund the unused part of any
            plan you paid us for directly in USDC. Store plans are refunded through the store. The parts of these
            terms that by their nature should continue (such as the limits on liability) still apply afterwards.
          </p>

          <h2>Warranties and liability</h2>
          <p>
            Glyf is provided &ldquo;as is&rdquo; and &ldquo;as available&rdquo;, without warranties of any kind, to
            the extent the law allows. We don&rsquo;t promise that Glyf will be error-free, always available, or that
            its results will be accurate.
          </p>
          <p>
            To the extent the law allows, we are not liable for indirect or consequential losses, lost profits or
            data, or for losses from tokens, prices, swaps, transactions you sign or services run by others. Our total
            liability to you for any claim about Glyf is limited to the greater of what you paid us in the 12 months
            before the claim and US$50. Nothing in these terms limits liability that can&rsquo;t be limited by law,
            or takes away rights you have as a consumer where you live.
          </p>

          <h2>Governing law</h2>
          <p>
            These terms are governed by the laws of India. Disputes will be decided by the courts of India, unless
            the law where you live gives you the right to bring them in your own courts. Before going to court,
            please email us so we can try to sort it out.
          </p>

          <h2>Changes</h2>
          <p>
            If these terms change, we will update this page and the date at the top, and tell you in the app when the
            change matters. Using Glyf after a change takes effect means you accept the new terms.
          </p>

          <h2>Contact</h2>
          <p>
            Arpit Singh, Glyf: <a href={`mailto:${EMAIL}`}>{EMAIL}</a>.
          </p>
        </div>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <Wordmark href="/" label="Glyf home" />
          <p className="footer-legal">© 2026 Glyf · iPhone and Android · <a href="/privacy">Privacy</a></p>
        </div>
      </footer>
    </>
  );
}
