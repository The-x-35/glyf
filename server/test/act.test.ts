import { signedInApp } from "./helpers.js";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { aroundPlace, checkPlan, dropPlaceholders, dropSelfTalk, hasPlaceholder, keepsExact, keepsNumbers, listInsert, looksLikeRewrite,
  mathQuestion, needsTidy, parsePlan, parseRewriteOptions, placeInsert, placeName, planByRules, priceAsked, rewriteStyles, rewriteTarget,
  searchLike, tidyWritten, todayLine } from "../src/lib/act.js";
import { lastOutboundForTests } from "../src/providers/openrouter.js";
import { withCategory } from "../src/lib/search.js";
import type { PlaceCard } from "../src/lib/searchcards.js";
import { renderPage } from "../src/lib/pages.js";

/** Hold space → act on the typed intent. Rules route the obvious cases for
 *  free; the model only decides the rest, and nothing is invented. */

beforeAll(() => {
  env.mockAI = true;               // model calls burn zero quota
  process.env.MOCK_AI = "true";    // search providers answer from fixtures
});

describe("everyday asks the rules answer without a model (2026-09-28 audit)", () => {
  it("hears a price asked for, and only for a coin or stock", () => {
    for (const t of ["price of sol", "sol price", "how much is 1 sol", "aapl stock price", "whats tesla trading at",
      "what is the price of bitcoin?", "$sol", "price of pepe coin"]) {
      expect(priceAsked(t), t).not.toBeNull();
      expect(planByRules(t)?.intent, t).toBe("answer");
    }
    for (const t of ["how much is rent", "ticket price", "what is the house price", "price of petrol", "how much is it"]) {
      expect(priceAsked(t), t).toBeNull();
    }
  });

  it("writes a letter or a wish asked for by name", () => {
    for (const t of ["leave application for 2 days fever", "birthday wish for my sister", "resignation letter",
      "email to my landlord about the leak", "sick leave mail for tomorrow"]) {
      expect(planByRules(t)?.intent, t).toBe("write");
    }
    // Telling someone about one is a message, not an ask.
    expect(planByRules("I sent my leave application yesterday")).toBeNull();
  });
});

describe("a message stays a message (routing audit, 2026-09-28)", () => {
  it("never turns a message that mentions food, a video or a time into a lookup", () => {
    for (const t of ["had a great dinner with u last night, thanks", "did u see the video i sent u",
      "my leave application got approved lets party", "sorry cant join standup today my son has a temperature",
      "are you free for lunch tomorrow?", "this song is stuck in my head", "we should get the best pizza in town tonight",
      "give me a call when you're free", "plan for tomorrow is set, see u", "list of things i need from the store: milk, eggs",
      "make sure you bring the keys", "great lunch today", "best dinner ever", "the pizza here is good",
      "perfect weather for a picnic", "birthday wishes to you too", "lets meet at third wave coffee indiranagar at 6"]) {
      expect(planByRules(t), t).toBeNull();
    }
  });

  it("still routes what is asked the way a search or a request is", () => {
    const cases: [string, string][] = [
      ["write a caption for my beach sunset photo", "write"], ["give me 5 captions for this photo", "write"],
      ["suggest names for my cat", "write"], ["plan a 3 day trip to goa", "write"],
      ["thank you note for my teacher", "write"], ["what time is it", "answer"], ["time in tokyo", "answer"],
      ["sunset in paris", "answer"], ["will it rain tomorrow", "answer"], ["weather in bangalore tomorrow", "answer"],
      ["50 euros in dollars", "answer"], ["$100 in inr", "answer"], ["how much is 1 sol in euros", "answer"],
      ["cafes in indiranagar", "places"], ["best biryani near indiranagar", "places"], ["good hotels in goa", "places"],
      ["send me the dune part 2 trailer", "video"], ["funny cat videos", "video"], ["nearest metro station", "place"],
      // Suggest audit, 2026-09-29: a courtesy first, a "where can i", a trade.
      ["please find me a good sushi place in brooklyn", "places"], ["find me a good sushi place in brooklyn pls", "places"],
      ["where can i get good tacos in austin", "places"], ["where to get good tacos in austin", "places"],
      ["know any good dentists around here", "places"], ["where can i buy a charger near me", "places"],
    ];
    for (const [t, intent] of cases) expect(planByRules(t)?.intent, t).toBe(intent);
    // Write audit, 2026-09-29: words in another language, and what to say to whom.
    for (const t of ["how do you say thank you in japanese", "what's hello in french", "good morning in spanish",
      "say i love you in korean", "text to my boss saying im sick today", "text my boss saying i am sick today",
      "message my landlord about the broken heater", "email hr asking for 2 days off", "reply to her saying thanks"]) {
      expect(planByRules(t)?.intent, t).toBe("write");
    }
    for (const t of ["i'm fluent in spanish", "the movie is in french", "text me when you're home"]) {
      expect(planByRules(t)?.intent, t).not.toBe("write");
    }
    // A question for a fact, with or without its "?", is answered (2026-09-29).
    for (const t of ["who is the ceo of tesla", "why is the sky blue", "can dogs eat grapes?", "is pluto a planet",
      "what is the capital of peru"]) {
      expect(planByRules(t)?.intent, t).toBe("answer");
    }
    for (const t of ["are you coming tonight?", "can i come over later", "does it hurt?", "is that true",
      "how long until the bus comes", "whats up with you"]) {
      expect(planByRules(t)?.intent, t).not.toBe("answer");
    }
    // Asked of a person, nothing to search.
    for (const t of ["where can i find the report", "please tell me when you're home", "where do u want to eat"]) {
      expect(planByRules(t), t).toBeNull();
    }
  });

  it("reads a search as a search and a chat as a chat", () => {
    expect(searchLike("best biryani near indiranagar")).toBe(true);
    expect(searchLike("cafes near me")).toBe(true);
    expect(searchLike("which is the best cafe in indiranagar")).toBe(true);
    expect(searchLike("the pizza here is good")).toBe(false);
    expect(searchLike("had a great dinner with u")).toBe(false);
    expect(searchLike("great lunch today!")).toBe(false);
  });

  it("gives a question no tidy-up, and leaves other languages to the model", () => {
    for (const t of ["whats the capital of australia", "how do i get to indiranagar metro station",
      "is it going to rain today", "can u send me the invoice asap", "did u see the video i sent u",
      "hola no voy a poder ir a la cena hoy lo siento mucho", "bhai kal ka plan cancel kar de yaar mood nahi hai"]) {
      expect(needsTidy(t), t).toBe(false);
    }
    // A link's "?" is no question.
    expect(needsTidy("pls review the draft at https://docs.example.com/d/1?usp=sharing by fri")).toBe(true);
  });

  it("rewrites the message after an instruction, and writes a text asked for by name", () => {
    expect(rewriteTarget("make this sound professional: need the files asap")).toBe("need the files asap");
    expect(rewriteTarget("fix grammar: i has a apple")).toBe("i has a apple");
    expect(rewriteTarget("note: meeting at 5")).toBe("note: meeting at 5");
    expect(rewriteTarget("ya ok will send deck b4 6")).toBe("ya ok will send deck b4 6");
    expect(planByRules("apology text to my friend for missing her party")?.intent).toBe("write");
    expect(planByRules("birthday text for my dad")?.intent).toBe("write");
    expect(planByRules("happy anniversary message for my wife")?.intent).toBe("write");
    expect(planByRules("translate thank you so much to hindi")?.intent).toBe("write");
    expect(planByRules("how to make pancakes")?.intent).toBe("video");
  });

  it("keeps an answer to the answer, without the model's remarks on it", () => {
    expect(dropSelfTalk("Elon Musk is the CEO of Tesla. He has held this position since 2008. This information is " +
      "well-established and not time-sensitive. No current events change this fact."))
      .toBe("Elon Musk is the CEO of Tesla. He has held this position since 2008.");
    expect(dropSelfTalk("Canberra is the capital of Australia.")).toBe("Canberra is the capital of Australia.");
  });

  it("takes a second look at what the router says", () => {
    expect(checkPlan({ intent: "write", query: "x" }, "can u send me the invoice asap").intent).toBe("rewrite");
    expect(checkPlan({ intent: "video", query: "x" }, "this song is stuck in my head").intent).toBe("rewrite");
    // Asked of a friend, in Hindi or English, never of Glyf (it once answered
    // "bhai kidhar hai tu" with "I am an AI without a physical location").
    for (const text of ["bhai kidhar hai tu", "tum kab aa rahe ho", "aap kaise ho", "where r u bro", "yaar kitna time lagega"]) {
      expect(checkPlan({ intent: "answer", query: text }, text).intent, text).toBe("rewrite");
    }
    for (const text of ["who is the ceo of tesla", "how tall is the eiffel tower", "what does fomo mean"]) {
      expect(checkPlan({ intent: "answer", query: text }, text).intent, text).toBe("answer");
    }
    // Their own plans: only the people in the chat know (audit 2026-09-29,
    // "what time is the meeting tmrw" came back as an empty answer).
    for (const text of ["what time is the meeting tmrw", "where is the party tonight", "who is coming tonight",
      "what time is our flight", "when is the dinner"]) {
      expect(checkPlan({ intent: "answer", query: text }, text).intent, text).toBe("rewrite");
    }
    for (const text of ["where is the nearest atm", "what time does costco close", "who won the game last night"]) {
      expect(checkPlan({ intent: "answer", query: text }, text).intent, text).toBe("answer");
    }
    // A song's title may hold a "you"; a message about a song is still a message.
    expect(checkPlan({ intent: "video", query: "x" }, "ed sheeran shape of you").intent).toBe("video");
    expect(checkPlan({ intent: "video", query: "x" }, "this song is stuck in my head").intent).toBe("rewrite");
    expect(checkPlan({ intent: "video", query: "x" }, "did u see the video i sent u").intent).toBe("rewrite");
    expect(checkPlan({ intent: "place", query: "x" }, "had a great dinner at toit last night").intent).toBe("rewrite");
    expect(checkPlan({ intent: "answer", query: "x" }, "r u free tmrw").intent).toBe("rewrite");
    expect(checkPlan({ intent: "place", query: "x" }, "how do i get to indiranagar metro station").intent).toBe("place");
    expect(checkPlan({ intent: "write", query: "x" }, "a toast for my sister's wedding").intent).toBe("write");
    expect(checkPlan({ intent: "answer", query: "x" }, "can you tell me the time in tokyo").intent).toBe("answer");
    expect(checkPlan({ intent: "answer", query: "x" }, "whats up").intent).toBe("rewrite");
    expect(checkPlan({ intent: "answer", query: "x" }, "ok").intent).toBe("rewrite");
    expect(checkPlan({ intent: "answer", query: "x" }, "whats up with the stock market today").intent).toBe("answer");
  });
});

describe("a place inside a sentence", () => {
  const top: PlaceCard = { kind: "place", id: "p", title: "Third Wave Coffee Roasters",
    address: "12th Main Road, Indiranagar", url: "https://www.google.com/maps/search/?api=1&query=Third+Wave" };

  it("looks up the place, not the sentence", () => {
    expect(placeName("lets meet at third wave coffee indiranagar at 6")).toBe("third wave coffee indiranagar");
    expect(placeName("see you at Blue Tokai tomorrow at 5pm")).toBe("Blue Tokai");
    expect(placeName("Third Wave Coffee, Indiranagar")).toBe("Third Wave Coffee, Indiranagar");
  });

  it("keeps the sentence and adds the link; a name alone is the place; a way asked is directions", () => {
    expect(placeInsert("lets meet at third wave coffee indiranagar at 6", "third wave coffee indiranagar", top))
      .toBe(`lets meet at third wave coffee indiranagar at 6\n${top.url}`);
    expect(placeInsert("third wave coffee indiranagar", "third wave coffee indiranagar", top))
      .toBe(`${top.url}\nThird Wave Coffee Roasters`);
    expect(placeInsert("how do i get to third wave indiranagar", "third wave indiranagar", top))
      .toMatch(/^Third Wave Coffee Roasters\nhttps:\/\/www\.google\.com\/maps\/dir\/\?api=1&destination=/);
    expect(aroundPlace("where is third wave coffee indiranagar", "third wave coffee indiranagar")).toBe(false);
  });
});

describe("what is written goes in the chat as it is", () => {
  it("drops openers, notes and markdown, but not a wish that starts with Here's", () => {
    expect(tidyWritten("Sure! Here's a caption for your beach sunset photo:\n\n**Chasing sunsets** 🌅\n\nFeel free to adjust!"))
      .toBe("Chasing sunsets 🌅");
    expect(tidyWritten("Here's to a wonderful year ahead!")).toBe("Here's to a wonderful year ahead!");
    expect(tidyWritten("Regards,\n[Your Name]", { name: "Arpit" })).toBe("Regards,\nArpit");
  });

  it("finds and, as a last resort, removes placeholders", () => {
    expect(hasPlaceholder("Dear [Manager's Name],")).toBe(true);
    expect(hasPlaceholder("see [the doc](https://x.y)")).toBe(false);
    expect(dropPlaceholders("Dear [Manager's Name],\n\nI will be on leave on [Date] for an appointment.\n\nRegards,\n[Your Name]"))
      .toBe("Hello,\n\nI will be on leave for an appointment.\n\nRegards,");
    expect(dropPlaceholders("Subject: Leave Application - [Your Name]\n\nHi,")).toBe("Subject: Leave Application\n\nHi,");
  });

  it("dates a write where the writer is", () => {
    const at = new Date("2026-09-28T20:00:00Z");
    expect(todayLine("Asia/Kolkata", at)).toBe(
      "Today is Tuesday, September 29, 2026, 1:30 AM where the writer is; tomorrow is Wednesday, September 30, 2026.");
    expect(todayLine("Not/AZone", at)).toContain("Monday, September 28, 2026");
  });

  it("keeps links and email addresses letter for letter", () => {
    const typed = "pls review https://docs.example.com/d/1AbC?usp=sharing and mail priya.k@acme.io";
    expect(keepsExact(typed, "Please review https://docs.example.com/d/1AbC?usp=sharing and email priya.k@acme.io.")).toBe(true);
    expect(keepsExact(typed, "Please review the doc and email Priya.")).toBe(false);
  });
});

describe("POST /act, what is written", () => {
  it("never pastes a refusal, and asks for someone's details without filling in the writer's", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act", payload: {
      text: "write a message asking my landlord for his email address", deviceId: "write-dev-00000002",
      profile: { email: "me@example.com" } } });
    expect(res.statusCode).toBe(200);
    expect(res.json().intent).toBe("write");
    // The mock echoes the prompt's last line: the ask, with no profile before it.
    expect(lastOutboundForTests.at(-1)?.content).not.toContain("me@example.com");
  });
});

describe("planByRules", () => {
  it("routes place lists, single places, videos and computed answers", () => {
    expect(planByRules("coffee near me")?.intent).toBe("places");
    expect(planByRules("nearest ATM")?.intent).toBe("place");
    expect(planByRules("SF best italian restaurant")?.intent).toBe("places");
    expect(planByRules("lofi beats playlist")?.intent).toBe("video");
    expect(planByRules("12*7")?.intent).toBe("answer");
    expect(planByRules("100 usd to inr")?.intent).toBe("answer");
    expect(planByRules("sunset")?.intent).toBe("answer");
  });

  it("leaves ambiguous text to the model", () => {
    expect(planByRules("Times Square Starbucks")).toBeNull();
    expect(planByRules("World Cup today")).toBeNull();
    expect(planByRules("running late dont order without me")).toBeNull();
    expect(planByRules("   ")).toBeNull();
  });
});

describe("parsePlan", () => {
  it("reads the first JSON object even when the model adds prose", () => {
    expect(parsePlan('Sure! {"intent":"place","query":"Starbucks Times Square"} done', "x"))
      .toEqual({ intent: "place", query: "Starbucks Times Square" });
  });

  it("rejects unknown intents and falls back to the typed query", () => {
    expect(parsePlan('{"intent":"launch_rocket","query":"x"}', "x")).toBeNull();
    expect(parsePlan('{"intent":"answer"}', "World Cup today"))
      .toEqual({ intent: "answer", query: "World Cup today" });
    expect(parsePlan("no json here", "x")).toBeNull();
  });

  it("takes the model's word when it says something should be written", () => {
    expect(parsePlan('{"intent":"write","query":"birthday message for mom"}', "x"))
      .toEqual({ intent: "write", query: "birthday message for mom" });
  });
});

describe("listInsert", () => {
  it("drops one numbered line per place, each with its maps link", () => {
    const places: PlaceCard[] = [
      { kind: "place", id: "a", title: "Flour + Water", rating: 4.8, address: "Mission, SF",
        url: "https://maps.google.com/?q=a" },
      { kind: "place", id: "b", title: "Acquerello", url: "https://maps.google.com/?q=b" },
    ];
    expect(listInsert("SF best italian", places)).toBe(
      "SF best italian\n1. Flour + Water · 4.8★ · Mission, SF\nhttps://maps.google.com/?q=a\n" +
      "2. Acquerello\nhttps://maps.google.com/?q=b");
  });
});

describe("POST /act", () => {
  const post = async (text: string, extra: Record<string, unknown> = {}) => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/act",
      payload: { text, deviceId: "test-device-act", ...extra },
    });
    return { status: res.statusCode, body: res.json() };
  };

  const freeRuns = env.freeRunsPerDay;
  afterEach(() => { env.freeRunsPerDay = freeRuns; });

  it("turns a place list request into place cards and a pasteable list", async () => {
    const { status, body } = await post("coffee near me");
    expect(status).toBe(200);
    expect(body.intent).toBe("places");
    expect(body.cards.map((c: PlaceCard) => c.kind)).toEqual(["place", "place"]);
    // Dev publishes the list as a live page on this server.
    expect(body.page).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/p\/[\w-]{12}$/);
    expect(body.insert).toBe(`coffee near me\n${body.page}`);
  });

  it("serves the live page with every place, escaped, and 404s unknown ids", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act",
      payload: { text: "coffee near me", deviceId: "test-device-page" } });
    const id = String(res.json().page).split("/p/")[1];
    const page = await app.inject({ method: "GET", url: `/p/${id}` });
    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toContain("text/html");
    expect(page.body).toContain("Blue Tokai Coffee");
    expect(page.body).toContain("Third Wave Coffee");
    expect(page.body).toContain("Made with");
    expect((await app.inject({ method: "GET", url: "/p/nope-not-a-page" })).statusCode).toBe(404);
  });

  it("returns a video card pasted Gboard-style", async () => {
    const { body } = await post("lofi beats video");
    expect(body.intent).toBe("video");
    expect(body.insert).toBe("https://youtu.be/jfKfPfyJRdk\n🎥 lofi hip hop radio — beats to relax/study to");
  });

  it("answers computable questions from the web vertical", async () => {
    const { body } = await post("sunset");
    expect(body.intent).toBe("answer");
    // The mock card carries no sentence of its own, so value and sub are
    // joined; a real card pastes its `say` line (see the next test).
    expect(body.insert).toBe("6:13 PM, Sunset · today");
  });

  it("routes a sum asked in words to an answer, not a rewrite", async () => {
    // Search is mocked here (a fixed card), so this pins the routing; the
    // calculator's sentence is pinned in search.test.ts.
    const { body } = await post("what is 18% of 2450?");
    expect(body.intent).toBe("answer");
    expect(planByRules("what is 18% of 2450?")).toEqual({ intent: "answer", query: "18% of 2450" });
  });

  it("answers a question with the AI, not a Google link, unless it is about right now", async () => {
    // 2026-09-29: no search for now, "use ai only for all that too".
    const { body } = await post("who is the ceo of tesla");
    expect(body.intent).toBe("answer");
    expect(["ai", "mock"]).toContain(body.provider);
    expect(body.insert).not.toBe("");
    // Not the "See it on Google" hand-off that answered before.
    expect((body.cards ?? []).some((c: { id?: string }) => (c.id ?? "").startsWith("google:"))).toBe(false);
    // What is happening right now stays a hand-off: the AI can't know it.
    const { rightNow } = await import("../src/lib/answers.js");
    for (const t of ["who won the game last night", "india vs australia score", "news today", "bitcoin price right now"]) {
      expect(rightNow(t), t).toBe(true);
    }
    for (const t of ["who is the ceo of tesla", "who won the super bowl", "latest iphone", "who is the current president of france"]) {
      expect(rightNow(t), t).toBe(false);
    }
  });

  it("tidies an ordinary message instead of looking anything up", async () => {
    const { body } = await post("hey im late dont order without me");
    expect(body.intent).toBe("rewrite");
    expect(body.cards).toEqual([]);
    expect(body.text).toContain("hey im late dont order without me");
    expect(body.insert).toBe(body.text);
  });

  it("spends a run only when the model is asked", async () => {
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const send = (text: string, stream = false) => app.inject({ method: "POST", url: "/act",
      payload: { text, deviceId: "metered-device-act", stream } });
    // Worked out without a model: free, however many times.
    for (const text of ["2+5", "sunset", "2+5"]) expect((await send(text)).statusCode).toBe(200);
    // A tidy-up asks the model: the day's one run, then the refusal.
    const tidied = await send("hey im late dont order without me");
    expect(tidied.statusCode).toBe(200);
    expect(tidied.json().remaining).toBe(0);
    const blocked = await send("ya ok will send the deck b4 6");
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error).toContain("used up");
    const streamed = await send("ya ok will send the deck b4 6", true);
    expect(streamed.body).toContain("event: error");
    expect(streamed.body).toContain("used up");
    // Still free once the runs are gone.
    const sum = await send("2+5");
    expect(sum.statusCode).toBe(200);
    expect(sum.json().intent).toBe("answer");
  });

  it("serves static maps only for real coordinates, and only with a key", async () => {
    const app = signedInApp();
    const saved = process.env.GEOAPIFY_KEY;
    delete process.env.GEOAPIFY_KEY;
    const noKey = await app.inject({ method: "GET", url: "/search/staticmap?lat=40.75&lon=-73.98" });
    expect(noKey.statusCode).toBe(404);
    process.env.GEOAPIFY_KEY = "test-key";
    const bad = await app.inject({ method: "GET", url: "/search/staticmap?lat=91&lon=https://evil" });
    expect(bad.statusCode).toBe(404);
    if (saved === undefined) delete process.env.GEOAPIFY_KEY; else process.env.GEOAPIFY_KEY = saved;
  });

  it("rejects empty text without logging it", async () => {
    const { status } = await post("");
    expect(status).toBe(400);
  });
});

describe("renderPage", () => {
  it("escapes what it shows and never lets a card URL become script", () => {
    const html = renderPage({ title: "<script>x</script>", createdAt: 0, places: [
      { kind: "place", id: "1", title: "A&B <b>", url: "javascript:alert(1)" },
    ] });
    expect(html).not.toContain("<script>x");
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("A&amp;B &lt;b&gt;");
    expect(html).not.toContain("javascript:");
  });
});


describe("rewrite options", () => {
  it("offers Hinglish only where people write it", () => {
    expect(rewriteStyles({ country: "IN" }).map(s => s.id)).toContain("hinglish");
    expect(rewriteStyles({ country: "US" }).map(s => s.id)).not.toContain("hinglish");
  });
  it("reads the versions in row order and drops empty ones", () => {
    const styles = rewriteStyles({ country: "US" });
    const out = parseRewriteOptions(
      'here: {"work":"I will send it by 6 PM.","basic":"ya ok, will send it by 6","polite":"","shorter":"By 6."}',
      styles);
    expect(out.map(o => o.label)).toEqual(["Basic", "Professional", "Shorter"]);
  });
});

describe("a version keeps the numbers the writer typed", () => {
  it("drops a version that reads b4 6 as before you", () => {
    const typed = "ya ok will send deck b4 6";
    expect(keepsNumbers(typed, "Yes, I will send the deck before 6.")).toBe(true);
    expect(keepsNumbers(typed, "Yes, I will send the deck before six.")).toBe(true);
    expect(keepsNumbers(typed, "Haan ok, deck b4 6 bhej dunga.")).toBe(true);
    expect(keepsNumbers(typed, "Yes, I will send the deck before you.")).toBe(false);
  });
  it("reads amounts, times and counts however they are written", () => {
    expect(keepsNumbers("pay 2,450 by 5pm", "Please pay 2450 by 5 PM.")).toBe(true);
    expect(keepsNumbers("pay 2,450 by 5pm", "Please pay by 5 PM.")).toBe(false);
    expect(keepsNumbers("table for 4", "A table for four, please.")).toBe(true);
    expect(keepsNumbers("call me at 6:30", "Call me at 6:30.")).toBe(true);
    expect(keepsNumbers("call me at 6:30", "Call me at 6.")).toBe(false);
  });
  it("leaves shorthand and masked details alone", () => {
    expect(keepsNumbers("this is 4 u", "This is for you.")).toBe(true);
    expect(keepsNumbers("going 2 the mall gr8", "Going to the mall, great.")).toBe(true);
    expect(keepsNumbers("give me 1 min", "Give me a minute.")).toBe(true);
    expect(keepsNumbers("see u 2day, card is [[S1]]", "See you today. My card is [[S1]].")).toBe(true);
  });
});

describe("a plain reply standing in for the rewrite", () => {
  const typed = "hey im late dont order without me";

  it("accepts a message-shaped reply", () => {
    expect(looksLikeRewrite("Hey, I'm late. Don't order without me!", typed)).toBe(true);
  });

  it("refuses the model's working, however it starts", () => {
    expect(looksLikeRewrite(
      "We need to rewrite the message in each style, preserving facts exactly. The message: hey im late", typed)).toBe(false);
    expect(looksLikeRewrite("Here are the versions you asked for:", typed)).toBe(false);
    expect(looksLikeRewrite('{"basic": "Hey, I\'m late"', typed)).toBe(false);
  });

  it("refuses an essay for a one-line message", () => {
    expect(looksLikeRewrite("Hey. ".repeat(80), typed)).toBe(false);
  });
});

describe("mathQuestion", () => {
  it("finds the sum inside a question about one", () => {
    expect(mathQuestion("18% of 2450")).toBe("18% of 2450");
    expect(mathQuestion("what's 18% of 2450?")).toBe("18% of 2450");
    expect(mathQuestion("how much is 12 x 12")).toBe("12 * 12");
    expect(mathQuestion("calculate 2450/4")).toBe("2450/4");
  });
  it("leaves messages that only mention numbers alone", () => {
    expect(mathQuestion("meet at 5, table for 4")).toBeNull();
    expect(mathQuestion("what is the plan for 2025")).toBeNull();
    expect(mathQuestion("see you at 10-11")).toBeNull();
  });
});

describe("withCategory", () => {
  it("says a bank-named cash machine is an ATM, once", () => {
    expect(withCategory("Citibank", "service.financial.atm")).toBe("Citibank ATM");
    expect(withCategory("HDFC Bank ATM", "service.financial.atm")).toBe("HDFC Bank ATM");
    expect(withCategory("Blue Tokai", "catering.cafe")).toBe("Blue Tokai");
  });
});
