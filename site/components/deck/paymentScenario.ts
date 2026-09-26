import { money } from "../kb/data";
import type { Coach, KbSnapshot } from "../kb/Keyboard";
import { SCENARIOS, type Beat, type Scenario } from "../chat/scenarios";

/** The deck's payments chat: the site's own Semi scenario, plus the money
 *  question that comes up around a payment. Checking a token's price
 *  happens in the strip, so the chat never leaves the thread. Deck only:
 *  the live site keeps the shorter version. */

const SEND: Coach = { target: "send", label: "Send" };
const CLOSE: Coach = { target: "close", label: "Close" };

/** The chip is in the strip, so tap it and send. */
const chipCoach = (done: (t: string) => boolean) => (k: KbSnapshot): Coach => {
  if (done(k.text)) return SEND;
  if (k.panel) return CLOSE;
  return money(k.text) ? { target: "strip:money", label: "Tap" } : null;
};

const priced = (t: string) => /1 SOL = \$/i.test(t);

const TOKEN_PRICE: Beat = {
  them: ["btw what's sol at right now? 👀"],
  autotype: (k) => (k.text === "" ? "$sol" : null),
  goal: priced,
  coach: chipCoach(priced),
  reply: ["oh nice, up from yesterday 📈"],
  nudge: "any idea? 😅",
};

const semi = SCENARIOS.find((s) => s.id === "semi")!;

export const PAY_SCENARIO: Scenario = {
  ...semi,
  tag: "Private pay + prices",
  beats: [...semi.beats, TOKEN_PRICE],
};
