#!/usr/bin/env python3
"""Builds the scenario report from the recorded runs.

    python3 qa/build_report.py <out.html>

Reads qa/results/server.json, qa/results/android.json and
qa/device-scenarios.json; writes the HTML page to <out.html> and a plain
summary to qa/SCENARIOS.md.
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUN_DATE = "24 September 2026"

# What a person typed or did, for the server scenarios (their titles carry
# the situation; this is the literal input).
SERVER_INPUT = {
    "S01": "ya ok will send deck b4 6", "S02": "sry running late traffic is crazy",
    "S03": "kal meeting shift kar do please 4 baje", "S04": "can u send me the invoice asap (US)",
    "S05": "hey just wanted to check if you had a chance to look at the proposal…",
    "S06": "tidy this up pls its for the client", "S07": "who is coming tonight lmk",
    "S08": "sure my address is", "S09": "see you at the game tonight",
    "S10": "best biryani near indiranagar", "S11": "nearest atm", "S12": "cafes near me",
    "S13": "send me the dune part 2 trailer", "S14": "weather in bangalore tomorrow",
    "S15": "zxqv plorb wibble score today", "S16": "18% of 2450",
    "S21": "kal milte hain office ke baad", "S22": "see you after office tomorrow",
    "S23": "मुझे कल छुट्टी चाहिए", "S24": "நாளை சந்திப்போம்",
    "S25": "happy birthday, have a great year (→ Spanish)", "S26": "nos vemos mañana en la oficina",
    "S27": "ipl points table", "S28": "arijit singh live", "S29": "third wave coffee",
    "S30": "idea: Say no, politely", "S31": "idea: Turn it into a LinkedIn post",
    "S32": "Reply in Hinglish, on “hey can u send the report tmrw morning thx”",
    "S33": "a", "S34": "open Pay", "S35": "my card is 4111 1111 1111 1111 exp 12/29 cvv 123 pls pay the bill",
    "S36": "(empty message)", "S37": "otp is 482913 dont share it with anyone ok",
    "S38": "mera account number 4111111111111111 hai, paise bhej do", "S39": "100 usd to inr",
    "S40": "what is a black hole", "S41": "sunset", "S42": "lofi beats playlist",
    "S43": "good hotels in goa", "S44": "omg 😂😂 that was sooo funny cant breathe",
    "S45": "hey r u free for a call at 5 today", "S46": "so basically what happened was i reached the venue at like 7…",
    "S48": "i has went to the store yesterday and buyed milk",
    "S49": "meeting postpone ho gayi hai, kal 4 baje rakhte hain", "S50": "Phoenix Marketcity Bangalore",
}

SERVER_FIXED = {"S01", "S05", "S06", "S10", "S11", "S15", "S25", "S30", "S32", "S35", "S37", "S38",
                "S43", "S44", "S45", "S46", "S49", "S50"}

ANDROID_INPUT = {
    "S84": "i think teh plan works", "S85": "sry running late omw", "S86": "call at 5 ␣",
    "S87": "split is 3480/4", "S88": "sure my address is ␣", "S89": "my upi is ␣",
    "S91": "ya ok will send deck b4 6 (hold ␣)",
    "S92": "best biryani near indiranagar (hold ␣)", "S93": "tap g", "S94": "copy “Flight AI 2021 lands at 6:40”",
    "S95": "kal milte hain office ke baad ␣", "S96": "what a finish ␣ → 😊 key → 😂",
    "S97": "see you at the park tomorrow, slide left from ⌫",
    "S98": "take a screenshot → g → Clipboard → tap it",
    "S101": "system dark mode, then light",
    "S106": "see you ␣ → 😊 key → :-) → Classic → tap the first emoticon",
    "S107": "😊 key → GIF → Trending → tap a GIF",
    "S108": "😊 key → Stickers → Trending → tap a sticker",
    "S111": "calendar → + → Title “lunch with sam tomorrow 1pm” → Add → tap the event",
    "S112": "dinner friday 8pm → tap the chip → Add",
    "S117": "Google not connected → calendar → camera",
    "S118": "Booking link cal.com/fake-host/30min → calendar → Book a time → first time → “sam lee sam@example.com ria@example.com” → Book it",
    "S120": "“grab a time cal.com/sam-lee/intro” → tap the Book chip → first time → Book it",
    "S125": "Google connected (stand-in) → calendar → camera",
    "S126": "Google connected (stand-in) → calendar → + → “review friday 3pm” → Invitees “sam@example.com” → Video call → Add",
    "S127": "Google not connected → calendar → + → “lunch with sam tomorrow 1pm” → Add",
    "S128": "M bound to Meet link, Google connected (stand-in) → hold M",
}
ANDROID_FIXED = {"S85", "S86", "S87", "S88", "S89", "S91"}

FIXES = [
    ("Server", "Card numbers, CVVs, OTPs, PINs, passwords, ID numbers, API keys and recovery phrases went to the AI models inside messages.",
     "Masked before every model call and put back in the reply. No model sees one; the rewrite still has it."),
    ("Server", "A search with nothing found pasted a Google link into the message.",
     "Nothing goes in; the panel says Nothing found and keeps Google one tap away."),
    ("Server", "“best biryani near indiranagar” and “nearest atm” found no places; addresses read like database rows.",
     "The area is found first and searched around; addresses read the way a person writes them."),
    ("Server", "Picking Spanish on the translate strip still translated to Hindi; Hinglish showed as “Hindi (Hinglish)”.",
     "A hand-picked direction always wins; languages show by plain name."),
    ("Server", "A stalled model left a rewrite hanging 9 to 12 seconds.",
     "A model that hasn’t started answering in 4 seconds is skipped for the next."),
    ("Server", "Rewrites turned “b4 6” into “before you”; Basic came back unchanged.",
     "Every version keeps times, numbers and names; Basic cleans the message up."),
    ("Server", "A built glyf answered a chat message with a formal email full of [Name] placeholders.",
     "Glyfs write text ready to send, as long as the message they answer."),
    ("Android", "The strip had no sum answers, no “my address is” details, no Pay chip and no Tidy this up.",
     "The whole smart strip is ported from iOS, rule for rule, with the same tests."),
    ("Android", "Holding space didn’t pass saved details to the AI.",
     "It does, when “Let AI use your saved details” is on, like iOS."),
    ("iPhone", "Tidy this up never appeared when a message ended with a space.",
     "Fixed: the suggestion is matched on the trimmed sentence."),
    ("Both", "After a number and a space, the keyboard stayed on numbers.",
     "Letters come back after the space, like Apple’s keyboard and Gboard."),
    ("Both", "“sry” was autocorrected to “dry”.",
     "92 everyday shorthand words (sry, tmrw, rn, lmk, omw, ngl…) are left as typed."),
    ("Both", "Rewrite versions showed two and a half rows over a wasted bottom bar.",
     "The list fills the panel; retry sits in the header."),
    ("iPhone", "The clipboard didn’t offer what you had just copied.",
     "“Paste what you copied” sits on top until it is used."),
    ("Both", "VoiceOver couldn’t reach menu tiles, clipboard cards, versions or the strip chip; toasts were silent; TalkBack read out internal ids.",
     "Every control has a spoken name; toasts are announced."),
    ("App", "Screens said “Translation HUD”, “Vault picker”, “Humanize”, with explainer lines under options.",
     "Vault, Translate, Rewrite. No explainers."),
    ("App", "Onboarding’s Google step showed a server setup error naming environment variables.",
     "The step only appears when Google sign-in works; errors never name server settings."),
    ("Both", "glyf:// links (the tour, Build your own, Pay) opened a second Home on top of the right screen, and a link that started the app was dropped.",
     "The app handles its own links, including the one that launched it."),
    ("App", "On Android the tour started with the keyboard down, or up but not reading the message.",
     "Each level brings the keyboard up attached to the message box."),
    ("Both", "A tour closed by force left its rings on the keyboard.",
     "Hints expire and are cleared when the app starts."),
    ("iPhone", "The g button, the suggestion card and Close sat 3pt above the keyboard’s top edge, where VoiceOver and UI tests can’t reach them.",
     "They stay inside the keyboard and keep their centre."),
    ("Server", "“18% of 2450” and “what is 12 x 12?” were tidied as messages; an answer pasted as “441 — 18% of 2450”.",
     "Worded sums reach the calculator and paste the card’s sentence: “18% of 2450 is 441”."),
    ("Server", "The Tidy this up chip took about 9 seconds: two model calls ran one after the other.",
     "They run together; the chip shows in about 3.5 seconds."),
    ("Android", "Search suggestions went out without the signed-in session and were turned away.",
     "They carry the session like every other call."),
    ("Both", "A 38-character webhook secret (whsec_…) reached clipboard history, and Android refused a copied Ethereum address.",
     "One shared filter on both keyboards: known key prefixes (webhook, Stripe, GitLab, AWS, Google and more), JWTs and random tokens are never kept; wallet addresses are."),
    ("Both", "An emoticon glued itself to the word before it (“swqaerm:-)”).",
     "It is spaced off the word, the way an emoji is."),
    ("Android", "The keyboard asked the photo index for screenshots on its main thread; right after a screenshot, with storage busy, Android reported it as not responding.",
     "Screenshots load in the background and join the clipboard when found; GIF and sticker files are written off the main thread too."),
    ("Android", "After a screenshot was copied, the strip’s paste chip read the image as text: its label held the PNG’s bytes, about 200,000 characters, read on the main thread.",
     "Only text (or a web link) counts as a copy for the chip, Paste, the g bar, skills and history; a picture is left as a picture."),
    ("Both", "Refusals and limit messages used dashes (“Too fast — wait a moment”).",
     "Plain sentences: “Too fast. Wait a moment and try again”."),
    ("Android", "Book a time glued its line to the link before it (“cal.com/sam-lee/introBooked for…”).",
     "Whatever the calendar types is a sentence of its own, as on iPhone."),
]

NEEDS_YOU = [
    ("GIFs and stickers in the emoji board", "KLIPY_APP_KEY on Railway (it is in the local server/.env since 24 September)",
     "Without it the GIF tab says GIFs aren't set up yet and Stickers shows Noto animated emoji. Real KLIPY GIFs and stickers were checked on both keyboards with the local key."),
    ("Google Calendar and Meet", "The Calendar API and Meet REST API switched on, and their two scopes added to the consent screen, in Google Cloud",
     "No key or secret: the phone talks to Google. S121 to S128 ran against qa/fake-google.mjs, and the booking scenarios against qa/fake-scheduling.mjs, never a real account or a real person's calendar."),
    ("Web results", "Brave Search API key", "S27 shows only the Google hand-off row without it."),
    ("Weather answers", "Google Weather or web search key", "S14 honestly says nothing found without it."),
    ("Google sign-in", "OAuth client id and secret", "The onboarding step stays hidden until then."),
    ("Ratings and open now", "Google Places key", "Places come from Geoapify on the dev server today, without ratings."),
]


def load():
    rows = []
    for r in json.loads((ROOT / "results/server.json").read_text()):
        verdict = "pass" if r["verdict"] == "pass" else "blocked" if r["verdict"].startswith("blocked") else "fail"
        rows.append({
            "id": r["id"], "surface": "Server", "area": r["area"], "title": r["title"],
            "input": SERVER_INPUT.get(r["id"], ""), "outcome": r["note"] or "",
            "verdict": verdict, "why": r["verdict"].split(":", 1)[1].strip() if ":" in r["verdict"] else "",
            "ms": r.get("ms"), "fixed": r["id"] in SERVER_FIXED,
        })
    for r in json.loads((ROOT / "device-scenarios.json").read_text()):
        rows.append({**r, "why": "", "ms": None, "fixed": bool(r.get("fixed"))})
    for r in json.loads((ROOT / "results/android.json").read_text()):
        rows.append({
            "id": r["id"], "surface": "Android", "area": "Keyboard", "title": r["title"],
            "input": ANDROID_INPUT.get(r["id"], ""), "outcome": r["note"].strip("'"),
            "verdict": r["verdict"], "why": "", "ms": None, "fixed": r["id"] in ANDROID_FIXED,
        })
    rows.sort(key=lambda x: int(x["id"][1:]))
    return rows


def esc(s):
    return html.escape(str(s), quote=True)


def clean_outcome(s):
    s = s.replace("\n", " / ")
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= 220 else s[:217].rstrip() + "…"


def build_html(rows, out):
    counts = {v: sum(1 for r in rows if r["verdict"] == v) for v in ("pass", "blocked", "fail")}
    surfaces = ["Server", "iPhone", "Android", "App"]
    labels = {"Server": "Server and AI", "iPhone": "iPhone keyboard", "Android": "Android keyboard", "App": "App"}
    by_surface = {s: [r for r in rows if r["surface"] == s] for s in surfaces}
    fixed_count = sum(1 for r in rows if r["fixed"])

    board = "".join(
        f'<a class="cap {r["verdict"]}" href="#{r["id"]}" title="{esc(r["id"])} · {esc(r["title"])}">'
        f'<span>{esc(r["id"][1:])}</span></a>' for r in rows)

    tallies = "".join(
        f'<div class="tally"><span class="tally-n">{len(by_surface[s])}</span>'
        f'<span class="tally-l">{labels[s]}</span></div>' for s in surfaces)

    fixes = "".join(
        f'<li class="fix"><span class="chip chip-{esc(p.lower())}">{esc(p)}</span>'
        f'<p class="was">{esc(was)}</p><p class="now">{esc(now)}</p></li>'
        for p, was, now in FIXES)

    needs = "".join(
        f'<li><span class="need-what">{esc(w)}</span><span class="need-key">{esc(k)}</span>'
        f'<span class="need-note">{esc(n)}</span></li>' for w, k, n in NEEDS_YOU)

    groups = []
    for s in surfaces:
        items = []
        for r in by_surface[s]:
            verdict_label = {"pass": "Pass", "blocked": "Needs a key", "fail": "Fail"}[r["verdict"]]
            fixed = '<span class="fixed">fixed in this run</span>' if r["fixed"] else ""
            ms = f'<span class="ms">{r["ms"]:,} ms</span>' if isinstance(r.get("ms"), int) and r["ms"] > 5 else ""
            why = f'<p class="why">{esc(r["why"])}</p>' if r["why"] else ""
            items.append(
                f'<li class="row" id="{esc(r["id"])}" data-surface="{esc(s)}" data-verdict="{esc(r["verdict"])}">'
                f'<span class="rid">{esc(r["id"])}</span>'
                f'<div class="rbody"><p class="rtitle">{esc(r["title"])}</p>'
                f'<p class="typed"><span class="k">typed</span><code>{esc(r["input"])}</code></p>'
                f'<p class="got"><span class="k">got</span>{esc(clean_outcome(r["outcome"]))}</p>{why}'
                f'<p class="meta">{esc(r["area"])}{fixed}{ms}</p></div>'
                f'<span class="verdict v-{esc(r["verdict"])}">{verdict_label}</span></li>')
        groups.append(
            f'<section class="group" data-group="{esc(s)}"><h3>{labels[s]} '
            f'<span class="gcount">{len(by_surface[s])}</span></h3><ol class="rows">{"".join(items)}</ol></section>')

    page = TEMPLATE.format(
        date=RUN_DATE, total=len(rows), passed=counts["pass"], blocked=counts["blocked"],
        failed=counts["fail"], fixed=fixed_count, board=board, tallies=tallies, fixes=fixes,
        fixes_n=len(FIXES), needs=needs, groups="".join(groups))
    Path(out).write_text(page)


def build_md(rows):
    lines = [
        "# Glyf scenario run", "",
        f"Run on {RUN_DATE} (the two app flows, S99 and S100, by hand on 17 September): the real "
        "keyboards (iPhone 17 Pro simulator, Android API 36 emulator) "
        "and the dev server with live models. Scripts: `qa/server-scenarios.mjs`, "
        "`app/ios/GlyfM0UITests/GlyfScenarioUITests.swift`, `qa/android-scenarios.mjs`.", "",
        f"{sum(r['verdict'] == 'pass' for r in rows)} pass, "
        f"{sum(r['verdict'] == 'blocked' for r in rows)} need a key, "
        f"{sum(r['verdict'] == 'fail' for r in rows)} fail, of {len(rows)}.", "",
        "| ID | Where | Scenario | Result |", "| --- | --- | --- | --- |",
    ]
    for r in rows:
        v = {"pass": "pass", "blocked": "needs a key", "fail": "fail"}[r["verdict"]]
        lines.append(f"| {r['id']} | {r['surface']} | {r['title'].replace('|', '/')} | {v} |")
    lines += ["", "## Fixed during the run", ""]
    lines += [f"- {p}: {was} {now}" for p, was, now in FIXES]
    lines += ["", "## Needs a key or account", ""]
    lines += [f"- {w}: {k}. {n}" for w, k, n in NEEDS_YOU]
    (ROOT / "SCENARIOS.md").write_text("\n".join(lines) + "\n")


TEMPLATE = """<title>Glyf Scenario Run</title>
<meta name="description" content="Every scenario run against the real keyboards and live server">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Schibsted+Grotesk:wght@500;600;700&family=Figtree:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
:root {{
  --ground: #f4f4f7;
  --surface: #ffffff;
  --ink: #17161c;
  --muted: #62606e;
  --rule: #e3e2ea;
  --accent: #6b4ef0;
  --accent-soft: #ece8fe;
  --pass: #1e7f4f;
  --pass-bg: #e3f2e9;
  --fail: #b23a26;
  --fail-bg: #fbe8e4;
  --blocked: #8a5a00;
  --blocked-bg: #fbefd8;
  --cap-shadow: #d6d5de;
  --display: "Schibsted Grotesk", "Helvetica Neue", Arial, sans-serif;
  --body: "Figtree", "Segoe UI", system-ui, sans-serif;
  --mono: "JetBrains Mono", "SFMono-Regular", Menlo, Consolas, monospace;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    --ground: #101015; --surface: #18171f; --ink: #eceaf4; --muted: #a29fb0; --rule: #2a2934;
    --accent: #a28cff; --accent-soft: #241f3d;
    --pass: #5ccb91; --pass-bg: #14281d; --fail: #f08a74; --fail-bg: #33191a;
    --blocked: #e4ae4f; --blocked-bg: #2e2513; --cap-shadow: #08080b;
  }}
}}
:root[data-theme="dark"] {{
  --ground: #101015; --surface: #18171f; --ink: #eceaf4; --muted: #a29fb0; --rule: #2a2934;
  --accent: #a28cff; --accent-soft: #241f3d;
  --pass: #5ccb91; --pass-bg: #14281d; --fail: #f08a74; --fail-bg: #33191a;
  --blocked: #e4ae4f; --blocked-bg: #2e2513; --cap-shadow: #08080b;
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--ground); color: var(--ink); font: 400 15px/1.55 var(--body); }}
.page {{ max-width: 1040px; margin: 0 auto; padding: 48px 24px 96px; display: grid; gap: 56px; }}
h1, h2, h3 {{ font-family: var(--display); text-wrap: balance; margin: 0; }}
h1 {{ font-size: clamp(34px, 5vw, 52px); line-height: 1.02; font-weight: 700; letter-spacing: -0.02em; }}
h1 .dot {{ display: inline-block; width: .17em; height: .17em; border-radius: 50%; background: var(--accent); transform: translate(.04em, -.62em); }}
h2 {{ font-size: 24px; font-weight: 600; letter-spacing: -0.01em; }}
h3 {{ font-size: 17px; font-weight: 600; display: flex; align-items: baseline; gap: 10px; }}
p {{ margin: 0; }}
.eyebrow {{ font: 500 12px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }}

.head {{ display: grid; gap: 28px; }}
.head-top {{ display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 40px; align-items: end; }}
.head-copy {{ display: grid; gap: 16px; max-width: 38rem; }}
.lede {{ color: var(--muted); font-size: 16px; max-width: 62ch; }}
.score {{ display: flex; gap: 22px; flex-wrap: wrap; font-variant-numeric: tabular-nums; }}
.score div {{ display: grid; gap: 2px; }}
.score b {{ font: 600 30px/1 var(--display); }}
.score span {{ font-size: 13px; color: var(--muted); }}
.score .s-pass b {{ color: var(--pass); }}
.score .s-blocked b {{ color: var(--blocked); }}
.score .s-fail b {{ color: var(--fail); }}

.board {{ display: grid; grid-template-columns: repeat(17, minmax(0, 1fr)); gap: 6px; padding: 14px; background: var(--surface); border-radius: 14px; border: 1px solid var(--rule); }}
.cap {{ height: 32px; border-radius: 6px; display: grid; place-items: center; text-decoration: none;
  font: 500 10px/1 var(--mono); box-shadow: 0 1.5px 0 var(--cap-shadow); transition: transform .12s ease; }}
.cap:hover, .cap:focus-visible {{ transform: translateY(-2px); outline: none; }}
.cap:focus-visible {{ box-shadow: 0 0 0 2px var(--accent); }}
.cap.pass {{ background: var(--pass-bg); color: var(--pass); }}
.cap.blocked {{ background: var(--blocked-bg); color: var(--blocked); }}
.cap.fail {{ background: var(--fail-bg); color: var(--fail); }}
.board-foot {{ grid-column: 1 / -1; display: flex; justify-content: space-between; font: 400 11px/1.4 var(--mono); color: var(--muted); padding-top: 6px; }}

.tallies {{ display: grid; gap: 10px; align-content: end; padding-bottom: 4px; }}
.tally {{ display: flex; align-items: baseline; gap: 8px; }}
.tally-n {{ font: 600 18px/1 var(--display); font-variant-numeric: tabular-nums; }}
.tally-l {{ color: var(--muted); font-size: 14px; }}

.section {{ display: grid; gap: 20px; }}
.section-head {{ display: grid; gap: 6px; }}
.section-head p {{ color: var(--muted); max-width: 62ch; }}

.fixes {{ list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 32px; }}
.fix {{ display: grid; grid-template-columns: 76px minmax(0, 1fr); column-gap: 14px; row-gap: 4px; padding: 14px 0; border-top: 1px solid var(--rule); }}
.fix .chip {{ grid-row: span 2; align-self: start; }}
.was {{ color: var(--muted); text-decoration: line-through; text-decoration-color: color-mix(in srgb, var(--fail) 55%, transparent); text-decoration-thickness: 1px; }}
.now {{ color: var(--ink); }}
.chip {{ font: 500 11px/1 var(--mono); letter-spacing: .02em; padding: 5px 7px; border-radius: 5px; background: var(--accent-soft); color: var(--accent); text-align: center; white-space: nowrap; }}
.chip-server {{ background: var(--surface); color: var(--muted); box-shadow: inset 0 0 0 1px var(--rule); }}

.needs {{ list-style: none; margin: 0; padding: 0; display: grid; gap: 0; background: var(--surface); border: 1px solid var(--rule); border-radius: 14px; overflow: hidden; }}
.needs li {{ display: grid; grid-template-columns: 180px 260px minmax(0, 1fr); gap: 16px; padding: 14px 18px; border-top: 1px solid var(--rule); align-items: baseline; }}
.needs li:first-child {{ border-top: 0; }}
.need-what {{ font-weight: 600; }}
.need-key {{ font: 400 13px/1.4 var(--mono); color: var(--blocked); }}
.need-note {{ color: var(--muted); }}

.filters {{ display: flex; flex-wrap: wrap; gap: 8px; position: sticky; top: 0; padding: 12px 0; background: var(--ground); z-index: 2; }}
.filters button {{ font: 500 13px/1 var(--body); color: var(--ink); background: var(--surface); border: 1px solid var(--rule); border-radius: 999px; padding: 8px 13px; cursor: pointer; }}
.filters button[aria-pressed="true"] {{ background: var(--ink); color: var(--ground); border-color: var(--ink); }}
.filters button:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
.filters .sep {{ width: 1px; background: var(--rule); margin: 0 4px; }}

.group {{ display: grid; gap: 10px; }}
.gcount {{ font: 500 12px/1 var(--mono); color: var(--muted); }}
.rows {{ list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--rule); border-radius: 14px; overflow: hidden; }}
.row {{ display: grid; grid-template-columns: 52px minmax(0, 1fr) auto; gap: 16px; padding: 16px 18px; border-top: 1px solid var(--rule); scroll-margin-top: 70px; }}
.row:first-child {{ border-top: 0; }}
.row:target {{ background: var(--accent-soft); }}
.rid {{ font: 500 13px/1.6 var(--mono); color: var(--muted); font-variant-numeric: tabular-nums; }}
.rbody {{ display: grid; gap: 6px; min-width: 0; }}
.rtitle {{ font-weight: 600; }}
.typed, .got {{ display: grid; grid-template-columns: 44px minmax(0, 1fr); gap: 8px; align-items: baseline; overflow-wrap: anywhere; }}
.k {{ font: 500 11px/1 var(--mono); text-transform: uppercase; letter-spacing: .06em; color: var(--muted); }}
code {{ font: 400 13px/1.5 var(--mono); color: var(--ink); background: var(--ground); border-radius: 5px; padding: 2px 6px; justify-self: start; }}
.got {{ color: var(--ink); }}
.why {{ color: var(--blocked); font-size: 14px; }}
.meta {{ display: flex; flex-wrap: wrap; gap: 6px 12px; font-size: 12.5px; color: var(--muted); }}
.fixed {{ color: var(--accent); font-weight: 500; }}
.ms {{ font-family: var(--mono); font-size: 12px; font-variant-numeric: tabular-nums; }}
.verdict {{ align-self: start; font: 600 12px/1 var(--body); padding: 6px 9px; border-radius: 999px; white-space: nowrap; }}
.v-pass {{ background: var(--pass-bg); color: var(--pass); }}
.v-blocked {{ background: var(--blocked-bg); color: var(--blocked); }}
.v-fail {{ background: var(--fail-bg); color: var(--fail); }}
.row[hidden], .group[hidden] {{ display: none !important; }}

.foot {{ color: var(--muted); font-size: 13px; border-top: 1px solid var(--rule); padding-top: 18px; }}
.foot code {{ font-size: 12px; }}

@media (max-width: 820px) {{
  .head-top {{ grid-template-columns: 1fr; }}
  .fixes {{ grid-template-columns: 1fr; }}
  .needs li {{ grid-template-columns: 1fr; gap: 4px; }}
  .board {{ grid-template-columns: repeat(10, minmax(0, 1fr)); }}
  .cap {{ height: 28px; }}
}}
@media (max-width: 520px) {{
  .row {{ grid-template-columns: 1fr; gap: 8px; }}
  .verdict {{ justify-self: start; }}
}}
@media (prefers-reduced-motion: reduce) {{ .cap {{ transition: none; }} }}
</style>

<main class="page">
  <header class="head">
    <div class="head-top">
    <div class="head-copy">
      <p class="eyebrow">Scenario run · {date}</p>
      <h1>{total} things people do with Glyf<span class="dot" aria-hidden="true"></span></h1>
      <p class="lede">Real keys tapped on the iPhone and Android keyboards, and real models and searches on the server. Anything that broke got fixed, then run again.</p>
      <div class="score">
        <div class="s-pass"><b>{passed}</b><span>pass</span></div>
        <div class="s-blocked"><b>{blocked}</b><span>need a key</span></div>
        <div class="s-fail"><b>{failed}</b><span>fail</span></div>
        <div><b>{fixed}</b><span>fixed during the run</span></div>
      </div>
    </div>
    <div class="tallies">{tallies}</div>
    </div>
    <nav class="board" aria-label="All {total} scenarios">{board}<div class="board-foot"><span>S01</span><span>S{total}</span></div></nav>
  </header>

  <section class="section" aria-labelledby="fixed-h">
    <div class="section-head">
      <h2 id="fixed-h">What the run found and fixed</h2>
      <p>{fixes_n} problems a person would have hit, struck through, with what happens now.</p>
    </div>
    <ul class="fixes">{fixes}</ul>
  </section>

  <section class="section" aria-labelledby="needs-h">
    <div class="section-head">
      <h2 id="needs-h">Waiting on a key or account</h2>
    </div>
    <ul class="needs">{needs}</ul>
  </section>

  <section class="section" aria-labelledby="log-h">
    <div class="section-head">
      <h2 id="log-h">Every scenario</h2>
    </div>
    <div class="filters" role="group" aria-label="Filter scenarios">
      <button type="button" data-surface="all" aria-pressed="true">All</button>
      <button type="button" data-surface="Server" aria-pressed="false">Server and AI</button>
      <button type="button" data-surface="iPhone" aria-pressed="false">iPhone</button>
      <button type="button" data-surface="Android" aria-pressed="false">Android</button>
      <button type="button" data-surface="App" aria-pressed="false">App</button>
      <span class="sep" aria-hidden="true"></span>
      <button type="button" data-verdict="fixed" aria-pressed="false">Fixed in this run</button>
      <button type="button" data-verdict="blocked" aria-pressed="false">Needs a key</button>
    </div>
    {groups}
  </section>

  <p class="foot">Scripts: <code>qa/server-scenarios.mjs</code>, <code>GlyfScenarioUITests.swift</code>, <code>qa/android-scenarios.mjs</code>. iPhone 17 Pro simulator on iOS 26.5, Android emulator on API 36, dev server with live models.</p>
</main>

<script>
(() => {{
  const surfaceButtons = [...document.querySelectorAll('.filters [data-surface]')];
  const verdictButtons = [...document.querySelectorAll('.filters [data-verdict]')];
  let surface = 'all';
  let verdict = null;
  const apply = () => {{
    document.querySelectorAll('.row').forEach(row => {{
      const okSurface = surface === 'all' || row.dataset.surface === surface;
      const okVerdict = !verdict
        || (verdict === 'fixed' ? row.querySelector('.fixed') !== null : row.dataset.verdict === verdict);
      row.hidden = !(okSurface && okVerdict);
    }});
    document.querySelectorAll('.group').forEach(group => {{
      group.hidden = !group.querySelector('.row:not([hidden])');
    }});
    surfaceButtons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.surface === surface)));
    verdictButtons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.verdict === verdict)));
  }};
  surfaceButtons.forEach(b => b.addEventListener('click', () => {{ surface = b.dataset.surface; apply(); }}));
  verdictButtons.forEach(b => b.addEventListener('click', () => {{
    verdict = verdict === b.dataset.verdict ? null : b.dataset.verdict;
    apply();
  }}));
}})();
</script>
"""

if __name__ == "__main__":
    rows = load()
    build_html(rows, sys.argv[1])
    build_md(rows)
    print(len(rows), "scenarios")
