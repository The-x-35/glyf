import type { Coach, KbSnapshot } from "../kb/Keyboard";
import type { Scenario } from "../chat/scenarios";

/** The deck's trading chat: the keyboard types a stop-loss in plain words,
 *  the strip offers it as a Definitive Flash order, the trade panel quotes
 *  it and Place order hands it to the person's own wallet to sign.
 *  Deck only: the live site's chats stay the eight everyday ones.
 *  Illustrative numbers (ETH at $3,452.18). */

const SEND: Coach = { target: "send", label: "Send" };
const CLOSE: Coach = { target: "close", label: "Close" };
const DELETE: Coach = { target: "key:backspace", label: "Delete" };

const STOP_LINE = "sell my eth if it drops below 3000";

/** The rest of `line` the keyboard still has to type, or null once it's typed
 *  (or the text went another way). */
const typeRest = (line: string, t: string) => (t !== line && line.startsWith(t) ? line.slice(t.length) : null);

const stopSet = (t: string) => t.includes("Stop-loss set");

/** The keyboard types the sentence, the strip offers the trade, the panel
 *  quotes it, and one tap places it. */
function tradeCoach(k: KbSnapshot, line: string, done: (t: string) => boolean, go: string): Coach {
  if (done(k.text)) return SEND;
  if (k.trading) return k.trading.stage === "placing" ? null : { target: "trade:go", label: go };
  if (k.panel) return CLOSE;
  if (k.trade) return { target: "strip:trade", label: "Tap" };
  return typeRest(line, k.text) ? null : DELETE;
}

export const TRADE_SCENARIO: Scenario = {
  id: "ryan",
  name: "Ryan",
  avatar: "📉",
  tint: "#0052ff",
  tag: "Definitive Flash",
  headline: ["Type a stop-loss.", "Flash places it."],
  beats: [
    {
      them: ["eth just dipped 5% 😬", "you protecting your bag or what?"],
      autotype: (k) => (k.panel ? null : typeRest(STOP_LINE, k.text)),
      chips: ["trade"],
      goal: stopSet,
      coach: (k) => tradeCoach(k, STOP_LINE, stopSet, "Tap"),
      reply: ["smart move 🧠", "flash watches it so you don't have to"],
      tapback: "🔥",
      nudge: "so are you selling or not? 👀",
    },
  ],
};
