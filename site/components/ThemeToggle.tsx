"use client";

import { MoonIcon, SunIcon } from "./kb/icons";

/** Flips light/dark and remembers it. The icon is picked by CSS from the
 *  same data-theme / prefers-color-scheme rules, so there's no hydration flash. */
export default function ThemeToggle() {
  const flip = () => {
    const root = document.documentElement;
    const now = root.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const next = now === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    try {
      localStorage.setItem("glyf-theme", next);
    } catch {}
    document.querySelectorAll('meta[name="theme-color"]').forEach((m) => m.setAttribute("content", next === "dark" ? "#000000" : "#ffffff"));
  };
  return (
    <button type="button" className="theme-toggle" onClick={flip} aria-label="Switch between light and dark">
      <MoonIcon className="i-moon" />
      <SunIcon className="i-sun" />
    </button>
  );
}
