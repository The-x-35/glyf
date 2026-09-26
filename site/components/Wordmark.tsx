/** The Glyf logo, as an image: the same wordmark Google's sign-in screen
 *  shows. Google's brand check matches the uploaded logo against images on
 *  the page, and a wordmark drawn in text isn't one. A light and a dark
 *  copy; the stylesheet shows the one for the page's theme. */
export default function Wordmark({ href, label, className = "" }: { href: string; label: string; className?: string }) {
  return (
    <a className={`wordmark wordmark-logo ${className}`.trim()} href={href} aria-label={label}>
      <img className="wordmark-light" src="/brand/glyf-wordmark-light.png" alt="Glyf" width={770} height={453} />
      <img className="wordmark-dark" src="/brand/glyf-wordmark-dark.png" alt="" aria-hidden="true" width={770} height={453} />
    </a>
  );
}
