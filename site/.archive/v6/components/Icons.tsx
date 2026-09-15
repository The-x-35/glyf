/** Stroke icons — the app's keyboard glyphs, redrawn for the web.
 *  (Emoji read as clipart next to this type; these don't.) */

const base = {
  width: 17,
  height: 17,
  viewBox: "0 0 20 20",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

export const CalendarIcon = () => (
  <svg {...base}>
    <rect x="2.8" y="4.2" width="14.4" height="13" rx="3" />
    <path d="M2.8 8.2h14.4M6.6 2.6v3M13.4 2.6v3" />
    <circle cx="7" cy="12" r="0.9" fill="currentColor" stroke="none" />
    <circle cx="10.6" cy="12" r="0.9" fill="currentColor" stroke="none" />
  </svg>
);

export const VaultIcon = () => (
  <svg {...base}>
    <rect x="2.2" y="4.4" width="15.6" height="11.2" rx="2.6" />
    <circle cx="7" cy="9.4" r="1.8" />
    <path d="M11.4 8h3.6M11.4 11.6h3.6" />
  </svg>
);

export const ClipboardIcon = () => (
  <svg {...base}>
    <rect x="4.2" y="3.8" width="11.6" height="13.4" rx="2.6" />
    <rect x="7.4" y="2" width="5.2" height="3.6" rx="1.4" />
    <path d="M7.6 10h4.8M7.6 13.2h3.2" />
  </svg>
);

export const NotesIcon = () => (
  <svg {...base}>
    <rect x="3.4" y="3" width="13.2" height="14" rx="2.8" />
    <path d="M6.6 7.4h6.8M6.6 10.4h6.8M6.6 13.4h4" />
  </svg>
);

export const PacksIcon = () => (
  <svg {...base}>
    <path d="M10 2.6 17 6.3l-7 3.7-7-3.7z" />
    <path d="M3 10l7 3.7 7-3.7" />
    <path d="M3 13.7l7 3.7 7-3.7" />
  </svg>
);

export const SunIcon = () => (
  <svg {...base}>
    <circle cx="10" cy="10" r="3.4" />
    <path d="M10 2.4v2M10 15.6v2M2.4 10h2M15.6 10h2M4.6 4.6l1.4 1.4M14 14l1.4 1.4M15.4 4.6 14 6M6 14l-1.4 1.4" />
  </svg>
);

export const CoinIcon = () => (
  <svg {...base}>
    <circle cx="10" cy="10" r="7.3" />
    <path d="M8.2 6.4v7.2M7 6.6h3.4a1.9 1.9 0 0 1 0 3.8H7h3.8a1.9 1.9 0 0 1 0 3.8H7M9.6 5v1.4M9.6 13.6V15" />
  </svg>
);

export const WandIcon = () => (
  <svg {...base}>
    <path d="M4 16 13.4 6.6" />
    <path d="m12.2 3.2.7 1.7 1.7.7-1.7.7-.7 1.7-.7-1.7-1.7-.7 1.7-.7z" />
    <path d="M16.4 10.2l.45 1.1 1.1.45-1.1.45-.45 1.1-.45-1.1-1.1-.45 1.1-.45z" />
  </svg>
);

export const SearchIcon = () => (
  <svg {...base}>
    <circle cx="8.6" cy="8.6" r="5.4" />
    <path d="M12.8 12.8 17 17" />
  </svg>
);
