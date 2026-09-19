import type { Metadata } from "next";
import Deck from "@/components/deck/Deck";
import "./deck.css";

export const metadata: Metadata = {
  title: "Glyf · Pitch deck",
  description: "Glyf, the AI keyboard that does the rest.",
  robots: { index: false, follow: false },
  alternates: { canonical: "/deck" },
};

export default function DeckPage() {
  return <Deck />;
}
