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

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: "Glyf — every key is a Glyf",
  description:
    "The agentic AI keyboard. Hold a key and your text proofreads, translates, summarizes — right where you type. iOS and Android.",
  alternates: { canonical: "/" },
  openGraph: {
    title: "Glyf — every key is a Glyf",
    description:
      "The agentic AI keyboard. Hold a key and your text transforms right where you type.",
    type: "website",
    url: SITE,
    siteName: "Glyf",
  },
  twitter: {
    card: "summary_large_image",
    title: "Glyf — every key is a Glyf",
    description: "Hold a key. It's already done.",
  },
};

export const viewport: Viewport = {
  themeColor: "#ffffff",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={inter.variable}>
      <body>{children}</body>
    </html>
  );
}
