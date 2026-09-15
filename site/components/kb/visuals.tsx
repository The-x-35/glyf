import { useId } from "react";

/** Small illustrations for answer cards. They draw with currentColor so the
 *  card's light/dark ink carries through; only the sun and rain keep colour. */

export function GoogleG({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 48 48" width="1em" height="1em" aria-hidden>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  );
}

/** The sun's path across today's sky, with the sun where it is at the time. */
export function SunArc({ rise = false }: { rise?: boolean }) {
  const id = useId().replace(/:/g, "");
  const t = rise ? 0.1 : 0.9;
  const a = Math.PI * (1 - t);
  const x = 100 + 80 * Math.cos(a);
  const y = 84 - 62 * Math.sin(a);
  return (
    <svg className="kb-sun" viewBox="0 0 200 100" preserveAspectRatio="xMidYMid meet" aria-hidden>
      <defs>
        <radialGradient id={`${id}-glow`}>
          <stop offset="0" stopColor="#ffd27a" stopOpacity="0.95" />
          <stop offset="1" stopColor="#ff8a3d" stopOpacity="0" />
        </radialGradient>
        <linearGradient id={`${id}-trail`} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stopColor="#ffb340" stopOpacity="0.1" />
          <stop offset="1" stopColor="#ff9f0a" />
        </linearGradient>
      </defs>
      <path d="M20 84A80 62 0 0 1 180 84" className="kb-sun-track" />
      <path d={`M20 84A80 62 0 0 1 ${x.toFixed(1)} ${y.toFixed(1)}`} className="kb-sun-trail" stroke={`url(#${id}-trail)`} />
      <line x1="4" y1="84" x2="196" y2="84" className="kb-sun-horizon" />
      <circle cx={x} cy={y} r="22" fill={`url(#${id}-glow)`} className="kb-sun-glow" />
      <circle cx={x} cy={y} r="7.5" className="kb-sun-disc" />
      <text x="20" y="98" textAnchor="middle" className="kb-sun-label">6:08 AM</text>
      <text x="180" y="98" textAnchor="middle" className="kb-sun-label">6:24 PM</text>
    </svg>
  );
}

export function WeatherGlyph() {
  return (
    <svg className="kb-wx" viewBox="0 0 120 90" aria-hidden>
      <circle cx="46" cy="32" r="15" className="kb-wx-sun" />
      <path d="M36 68h48a15 15 0 0 0 2.2-29.8A21 21 0 0 0 46 43a12.5 12.5 0 0 0-10 25z" className="kb-wx-cloud" />
      <path d="M52 76l-3 8M67 76l-3 8M82 76l-3 8" className="kb-wx-rain" />
    </svg>
  );
}

export function ClockFace({ h, m }: { h: number; m: number }) {
  const minute = (m / 60) * 360;
  const hour = ((h % 12) / 12) * 360 + m * 0.5;
  return (
    <svg className="kb-clock" viewBox="0 0 100 100" aria-hidden>
      <circle cx="50" cy="50" r="44" className="kb-clock-face" />
      {Array.from({ length: 12 }, (_, i) => (
        <line key={i} x1="50" y1="11" x2="50" y2={i % 3 ? 15 : 18} transform={`rotate(${i * 30} 50 50)`} className="kb-clock-tick" />
      ))}
      <line x1="50" y1="50" x2="50" y2="29" transform={`rotate(${hour} 50 50)`} className="kb-clock-hand" />
      <line x1="50" y1="50" x2="50" y2="17" transform={`rotate(${minute} 50 50)`} className="kb-clock-hand thin" />
      <circle cx="50" cy="50" r="3" className="kb-clock-pin" />
    </svg>
  );
}
