/** The card contract shared by the server, both keyboards and the site.
 *
 *  `/tools/run` returns flat text rows because glyf chains consume strings.
 *  The search suite needs structure instead — a thumbnail, a rating, a
 *  duration — so it gets its own typed endpoint (`POST /search`) and this
 *  is the shape that crosses the wire. Swift and Kotlin mirror it field for
 *  field; renaming anything here means renaming it in three more places.
 */

/** "shorts" (2026-11-06) is the YouTube Shorts tab: vertical videos of at
 *  most three minutes. Older clients never send it, so it is purely additive. */
export type Vertical = "web" | "yt" | "maps" | "shorts";

/** Every card can be inserted into the host app. The client composes the
 *  paste from these three fields (§ paste format, Gboard parity):
 *
 *      <url>
 *      <emoji> <title>
 *      <extra>
 *
 *  …or just `<url>` when the user picked link-only. */
export interface CardBase {
  /** Stable id for de-duplication and tap telemetry. */
  id: string;
  title: string;
  url: string;
  /** Prefix for the title line when pasting title+link. Gboard uses 🎥 for
   *  videos and 📍 for places, and nothing at all for plain web links. */
  emoji?: string;
  /** Optional third paste line — the street address on a place card. */
  extra?: string;
  /** An answer is sent as the answer ("Sunset's at 6:24 PM 🌇"), not as a
   *  search link. When set, a tap puts exactly this in the field. */
  say?: string;
}

/** The big answer at the top of the web tab: sunset time, temperature, a
 *  calculation, a definition. `art` tells the client which illustration to
 *  draw beside it — the site already draws the sun arc. */
export interface AnswerCard extends CardBase {
  kind: "answer";
  /** The headline value, rendered huge: "6:13 PM", "28°", "42". */
  value: string;
  /** The label under it: "Sunset · today". */
  sub?: string;
  art: "sun" | "weather" | "calc" | "define" | "none";
  /** Where the answer came from, shown small: "timeanddate.com". */
  source?: string;
}

export interface LinkCard extends CardBase {
  kind: "link";
  snippet?: string;
  /** Bare host, shown under the title: "en.wikipedia.org". */
  domain: string;
  thumb?: string;
}

export interface VideoCard extends CardBase {
  kind: "video";
  /** "liked" when it came from the signed-in user's own library. */
  source?: string;
  channel: string;
  /** "1:02:14", or absent for a live stream. */
  duration?: string;
  live?: boolean;
  thumb?: string;
  videoId: string;
}

/** A YouTube Short: a vertical video of at most three minutes, linked as
 *  youtube.com/shorts/<id> so it opens in the Shorts player. */
export interface ShortCard extends CardBase {
  kind: "short";
  channel: string;
  /** "0:27" — always present: a Short is never live. */
  duration: string;
  seconds: number;
  /** True when YouTube reports a taller-than-wide player. Such a card's
   *  thumbnail is YouTube's 9:16 frame centred on its own filler, so the
   *  client may show just that frame. Absent when YouTube didn't say. */
  portrait?: boolean;
  thumb?: string;
  videoId: string;
}

export interface PlaceCard extends CardBase {
  kind: "place";
  address?: string;
  rating?: number;
  ratingCount?: number;
  openNow?: boolean;
  /** "350 m" / "1.1 mi" — only when the client sent a location. */
  distance?: string;
  thumb?: string;
  lat?: number;
  lon?: number;
}

/** A suggested search — the trending and recent rows on the landing state.
 *  Tapping one runs the search rather than pasting, so it carries no emoji. */
export interface QueryCard extends CardBase {
  kind: "query";
  /** "trending" | "recent" — picks the leading icon. */
  source?: string;
}

export type SearchCard = AnswerCard | LinkCard | VideoCard | ShortCard | PlaceCard | QueryCard;

export interface SearchResponse {
  vertical: Vertical;
  query: string;
  cards: SearchCard[];
  /** Which upstream answered, so the app can show "results by Brave" and so
   *  we can tell a key outage from an empty result set. */
  provider: string;
}

/** How a tapped card becomes text in the host app.
 *
 *  Mirrors Gboard exactly (verified against its YouTube and Maps shares):
 *  the URL goes on the first line, the emoji-prefixed title on the second,
 *  and a place's address on a third. Link-only drops everything but the URL.
 *
 *  Lives on the server so the two keyboards and the site can never drift —
 *  each client ports this one function and its tests. */
export function composeInsert(
  card: Pick<CardBase, "title" | "url" | "emoji" | "extra" | "say">,
  mode: "titleAndLink" | "linkOnly",
): string {
  if (card.say?.trim()) return card.say.trim();
  if (mode === "linkOnly" || !card.title.trim()) return card.url;
  const lines = [card.url, `${card.emoji ? `${card.emoji} ` : ""}${card.title}`];
  if (card.extra?.trim()) lines.push(card.extra.trim());
  return lines.join("\n");
}
