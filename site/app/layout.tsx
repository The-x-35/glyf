import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import "./globals.css";

const inter = localFont({
  src: "../public/fonts/Inter-Variable.ttf",
  display: "swap",
  variable: "--font-inter",
});

/** Canonical home. Override with SITE_URL on preview deploys. */
const SITE = process.env.SITE_URL ?? "https://tryglyf.com";

const TITLE = "Glyf · Type less. Glyf more.";
const DESCRIPTION =
  "The AI keyboard for iPhone and Android. Hold a key to search, rewrite, translate and fill in your details, right where you type. Join the waitlist.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/" },
  openGraph: { title: TITLE, description: DESCRIPTION, type: "website", url: SITE, siteName: "Glyf" },
  twitter: { card: "summary", title: TITLE, description: "The AI keyboard that does the rest." },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
  width: "device-width",
  initialScale: 1,
};

/** Runs before first paint: a saved theme choice wins over the system one. */
const THEME = `try{var t=localStorage.getItem("glyf-theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
