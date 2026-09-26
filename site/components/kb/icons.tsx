/** Stroke icons on a 20-unit grid. They inherit colour and size from the
 *  parent (1em square), so a toolbar or a card can scale them with font-size. */

type P = { className?: string };

const S = ({ children, className }: P & { children: React.ReactNode }) => (
  <svg
    className={className}
    width="1em"
    height="1em"
    viewBox="0 0 20 20"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.7"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden
  >
    {children}
  </svg>
);

export const SearchIcon = (p: P) => (
  <S {...p}>
    <circle cx="8.8" cy="8.8" r="5.3" />
    <path d="m12.8 12.8 4 4" />
  </S>
);

export const ClipIcon = (p: P) => (
  <S {...p}>
    <rect x="4.5" y="3.8" width="11" height="13.4" rx="2.2" />
    <path d="M7.6 3.8V3a1 1 0 0 1 1-1h2.8a1 1 0 0 1 1 1v.8M7.5 9h5M7.5 12h3.4" />
  </S>
);

export const LockIcon = (p: P) => (
  <S {...p}>
    <rect x="4" y="8.6" width="12" height="8.6" rx="2.2" />
    <path d="M6.6 8.6V6.4a3.4 3.4 0 0 1 6.8 0v2.2" />
  </S>
);

export const TranslateIcon = (p: P) => (
  <S {...p}>
    <path d="M2.8 4.6h7.4M6.5 2.8v1.8M8.8 4.6c-.6 3-2.7 5.5-5.6 6.9M4.6 7.6c1 1.6 2.5 2.9 4.4 3.7" />
    <path d="m10.6 17.2 3-7.2 3 7.2M11.6 15h4" />
  </S>
);

export const EmojiIcon = (p: P) => (
  <S {...p}>
    <circle cx="10" cy="10" r="7.2" />
    <path d="M7 11.8c.8 1.1 1.8 1.7 3 1.7s2.2-.6 3-1.7" />
    <path d="M7.6 7.9v.4M12.4 7.9v.4" strokeWidth="2.1" />
  </S>
);

export const ShiftIcon = ({ className, on }: P & { on?: boolean }) => (
  <svg className={className} width="1em" height="1em" viewBox="0 0 20 20" aria-hidden>
    <path
      d="M10 3.2 3.4 10.1h3.5v6h6.2v-6h3.5z"
      fill={on ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinejoin="round"
    />
  </svg>
);

export const BackspaceIcon = (p: P) => (
  <S {...p}>
    <path d="M7.4 4.6h9a1.6 1.6 0 0 1 1.6 1.6v7.6a1.6 1.6 0 0 1-1.6 1.6h-9L2.6 10z" />
    <path d="m9.8 7.8 4.4 4.4m0-4.4-4.4 4.4" />
  </S>
);

export const ReturnIcon = (p: P) => (
  <S {...p}>
    <path d="M16.2 4.8v5a2.2 2.2 0 0 1-2.2 2.2H4.6" />
    <path d="m7.6 8.8-3 3.2 3 3.2" />
  </S>
);

export const ArrowUpIcon = (p: P) => (
  <S {...p}>
    <path d="M10 15.6V4.8M5.4 9.2 10 4.6l4.6 4.6" strokeWidth="2" />
  </S>
);

export const CloseIcon = (p: P) => (
  <S {...p}>
    <path d="m5.6 5.6 8.8 8.8m0-8.8-8.8 8.8" />
  </S>
);

export const PinIcon = (p: P) => (
  <S {...p}>
    <path d="M10 17.6s5.4-4.9 5.4-9.4a5.4 5.4 0 1 0-10.8 0c0 4.5 5.4 9.4 5.4 9.4z" />
    <circle cx="10" cy="8.2" r="1.9" />
  </S>
);

export const PlayRectIcon = (p: P) => (
  <S {...p}>
    <rect x="2.4" y="4.6" width="15.2" height="10.8" rx="3.2" />
    <path d="M8.6 7.8v4.4l3.8-2.2z" fill="currentColor" strokeWidth="1.2" />
  </S>
);

export const PlayIcon = (p: P) => (
  <svg className={p.className} width="1em" height="1em" viewBox="0 0 20 20" aria-hidden>
    <path d="M6.4 4.4v11.2L15.6 10z" fill="currentColor" />
  </svg>
);

export const PauseIcon = (p: P) => (
  <svg className={p.className} width="1em" height="1em" viewBox="0 0 20 20" aria-hidden>
    <rect x="5.4" y="4.4" width="3.2" height="11.2" rx="1" fill="currentColor" />
    <rect x="11.4" y="4.4" width="3.2" height="11.2" rx="1" fill="currentColor" />
  </svg>
);

export const CheckIcon = (p: P) => (
  <S {...p}>
    <path d="m4.8 10.4 3.4 3.4 7-7.2" strokeWidth="2" />
  </S>
);

export const SparkIcon = (p: P) => (
  <S {...p}>
    <path d="M10 2.8c.5 3.6 1.9 5 5.4 5.5-3.5.5-4.9 1.9-5.4 5.5-.5-3.6-1.9-5-5.4-5.5 3.5-.5 4.9-1.9 5.4-5.5z" />
    <path d="M15.6 13.2c.2 1.5.8 2.1 2.2 2.3-1.4.2-2 .8-2.2 2.3-.2-1.5-.8-2.1-2.2-2.3 1.4-.2 2-.8 2.2-2.3z" />
  </S>
);

export const WandIcon = (p: P) => (
  <S {...p}>
    <path d="m3.4 16.6 9.2-9.2M11.2 5.9l2.9 2.9" />
    <path d="M15 2.6v2.6M13.7 3.9h2.6M17 7.6v1.8M16.1 8.5h1.8" />
  </S>
);

export const UndoIcon = (p: P) => (
  <S {...p}>
    <path d="M6.4 7.4h6.2a3.8 3.8 0 0 1 0 7.6H8.8" />
    <path d="m9 4.6-2.8 2.8L9 10.2" />
  </S>
);

export const ListIcon = (p: P) => (
  <S {...p}>
    <path d="M8 5.6h8.4M8 10h8.4M8 14.4h8.4" />
    <path d="M3.8 5.6h.2M3.8 10h.2M3.8 14.4h.2" strokeWidth="2.4" />
  </S>
);

export const BoltIcon = (p: P) => (
  <S {...p}>
    <path d="M11 2.6 4.6 11.2h5l-1 6.2 6.4-8.6h-5z" />
  </S>
);

export const CloudIcon = (p: P) => (
  <S {...p}>
    <path d="M6 15.6h8.2a3.4 3.4 0 0 0 .5-6.8A5 5 0 0 0 5 9.4a3.1 3.1 0 0 0 1 6.2z" />
  </S>
);

export const GridIcon = (p: P) => (
  <S {...p}>
    <rect x="3.4" y="3.4" width="5.2" height="5.2" rx="1.4" />
    <rect x="11.4" y="3.4" width="5.2" height="5.2" rx="1.4" />
    <rect x="3.4" y="11.4" width="5.2" height="5.2" rx="1.4" />
    <rect x="11.4" y="11.4" width="5.2" height="5.2" rx="1.4" />
  </S>
);

export const QuoteIcon = (p: P) => (
  <S {...p}>
    <path d="M3.6 10.6h4.2v5H3.6zM3.6 10.6c0-3 1-4.8 3.4-6M12.2 10.6h4.2v5h-4.2zM12.2 10.6c0-3 1-4.8 3.4-6" />
  </S>
);

export const SunIcon = (p: P) => (
  <S {...p}>
    <circle cx="10" cy="10" r="3.4" />
    <path d="M10 2.4v1.6M10 16v1.6M2.4 10H4M16 10h1.6M4.6 4.6l1.1 1.1M14.3 14.3l1.1 1.1M4.6 15.4l1.1-1.1M14.3 5.7l1.1-1.1" />
  </S>
);

export const MoonIcon = (p: P) => (
  <S {...p}>
    <path d="M16.2 12.2A6.8 6.8 0 0 1 7.8 3.8a6.8 6.8 0 1 0 8.4 8.4z" />
  </S>
);

export const StarIcon = (p: P) => (
  <svg className={p.className} width="1em" height="1em" viewBox="0 0 20 20" aria-hidden>
    <path
      d="m10 2.6 2.2 4.6 5 .6-3.7 3.5 1 5-4.5-2.5-4.5 2.5 1-5L2.8 7.8l5-.6z"
      fill="currentColor"
    />
  </svg>
);

export const PlusIcon = (p: P) => (
  <S {...p}>
    <path d="M10 4.4v11.2M4.4 10h11.2" strokeWidth="1.8" />
  </S>
);

export const MicIcon = (p: P) => (
  <S {...p}>
    <rect x="7.4" y="2.8" width="5.2" height="9.4" rx="2.6" />
    <path d="M4.8 9.6a5.2 5.2 0 0 0 10.4 0M10 14.8v2.6" />
  </S>
);

export const IdCardIcon = (p: P) => (
  <S {...p}>
    <rect x="2.6" y="4.4" width="14.8" height="11.2" rx="2.2" />
    <circle cx="7.2" cy="9" r="1.6" />
    <path d="M4.8 13c.5-1.2 1.3-1.8 2.4-1.8s1.9.6 2.4 1.8M11.6 8.4h3.6M11.6 11.2h2.6" />
  </S>
);

export const SendIcon = (p: P) => (
  <svg className={p.className} width="1em" height="1em" viewBox="0 0 24 24" aria-hidden>
    <path d="M3.4 20.4 21 12 3.4 3.6l.01 6.53L15 12 3.41 13.87z" fill="currentColor" />
  </svg>
);

export const WalletIcon = (p: P) => (
  <S {...p}>
    <rect x="2.8" y="5" width="14.4" height="11.4" rx="2.4" />
    <path d="M13.4 10.7h3.8M4.8 5l7.8-2.4a1.6 1.6 0 0 1 2 1.5V5" />
  </S>
);

export const SwapIcon = (p: P) => (
  <S {...p}>
    <path d="M6.2 3.6v12.2m0 0-3-3m3 3 3-3M13.8 16.4V4.2m0 0-3 3m3-3 3 3" />
  </S>
);

export const PasteIcon = (p: P) => (
  <S {...p}>
    <rect x="4.5" y="3.8" width="11" height="13.4" rx="2.2" />
    <path d="M7.6 3.8V3a1 1 0 0 1 1-1h2.8a1 1 0 0 1 1 1v.8M10 7.6v6m0 0-2.4-2.4M10 13.6l2.4-2.4" />
  </S>
);

export const ShieldIcon = (p: P) => (
  <S {...p}>
    <path d="M10 2.6 4 4.9v4.6c0 3.8 2.5 6.6 6 8 3.5-1.4 6-4.2 6-8V4.9z" />
    <path d="m7.4 10.1 1.8 1.8 3.5-3.6" />
  </S>
);

export const CalendarIcon = (p: P) => (
  <S {...p}>
    <rect x="3" y="4.2" width="14" height="12.8" rx="2.6" />
    <path d="M3 8.2h14M7 2.6v3.2M13 2.6v3.2" />
  </S>
);

export const CalendarCheckIcon = (p: P) => (
  <S {...p}>
    <rect x="3" y="4.2" width="14" height="12.8" rx="2.6" />
    <path d="M3 8.2h14M7 2.6v3.2M13 2.6v3.2m-5.6 7.1 1.7 1.7 3.2-3.3" />
  </S>
);

export const VideoIcon = (p: P) => (
  <S {...p}>
    <rect x="2.4" y="5.4" width="10.8" height="9.2" rx="2.4" />
    <path d="m13.2 8.8 4.4-2.6v7.6l-4.4-2.6" />
  </S>
);

export const PersonIcon = (p: P) => (
  <S {...p}>
    <circle cx="10" cy="7" r="3.2" />
    <path d="M3.8 17c.8-3.2 3.3-5 6.2-5s5.4 1.8 6.2 5" />
  </S>
);

export const LinkIcon = (p: P) => (
  <S {...p}>
    <path d="M8.6 11.4a3.2 3.2 0 0 0 4.5 0l2.6-2.6a3.2 3.2 0 0 0-4.5-4.5l-1 1" />
    <path d="M11.4 8.6a3.2 3.2 0 0 0-4.5 0l-2.6 2.6a3.2 3.2 0 0 0 4.5 4.5l1-1" />
  </S>
);

export const GifIcon = (p: P) => (
  <S {...p}>
    <rect x="2.4" y="4.6" width="15.2" height="10.8" rx="2.6" />
    <path d="M8.4 8.4H6.9a1.6 1.6 0 0 0-1.6 1.6v0a1.6 1.6 0 0 0 1.6 1.6h1.5V10.3H7.6M10.6 8.4v3.2M13.1 11.6V8.4h2M13.1 10h1.6" strokeWidth="1.4" />
  </S>
);
