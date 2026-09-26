import { VAULT } from "../kb/data";
import type { Coach, KbSnapshot } from "../kb/Keyboard";
import { SCENARIOS, type Beat, type Scenario } from "../chat/scenarios";

/** The deck's math chat: the site's Zoya scenario, but the second ask is for
 *  a wallet rather than a UPI id, so the slide reads as math plus crypto for
 *  an audience that does not use UPI. Deck only. */

const SEND: Coach = { target: "send", label: "Send" };
const CLOSE: Coach = { target: "close", label: "Close" };

const wallet = VAULT.find((v) => v.id === "wallet")!.value;

const WALLET_ASK: Beat = {
  them: ["what's your wallet? I'll send it in usdc 💸"],
  autotype: (k) => (k.text === "" ? "my wallet is " : null),
  goal: (t) => t.includes(wallet),
  coach: (k: KbSnapshot): Coach => {
    if (k.text.includes(wallet)) return SEND;
    if (k.panel === "vault") return { target: "vault:wallet", label: "Tap Solana" };
    if (k.mine === "wallet") return { target: "strip:vault", label: "Tap" };
    if (k.panel) return CLOSE;
    return { target: "key:v", label: "Hold V" };
  },
  reply: ["sent ✅ nobody can see it either 🥷"],
  tapback: "👍",
  nudge: "your wallet? 🙏",
};

const zoya = SCENARIOS.find((s) => s.id === "zoya")!;

export const MATH_SCENARIO: Scenario = {
  ...zoya,
  tag: "Math + crypto",
  headline: ["Do the math.", "Get paid."],
  beats: [zoya.beats[0], WALLET_ASK],
};
