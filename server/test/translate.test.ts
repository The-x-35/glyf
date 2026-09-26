import { describe, expect, it } from "vitest";
import { chooseTarget, languageName, latinLanguage, parseTranslation, scriptLanguage } from "../src/lib/translate.js";

const req = { text: "", primary: "English", secondary: "Hindi" };

describe("translate direction", () => {
  it("sends the first language to the other one", () => {
    expect(chooseTarget("English", req)).toBe("Hindi");
  });
  it("brings every other language back to the first", () => {
    expect(chooseTarget("Hindi", req)).toBe("English");
    expect(chooseTarget("Spanish", req)).toBe("English");
  });
  it("follows a hand-picked target", () => {
    expect(chooseTarget("English", { ...req, target: "French" })).toBe("French");
  });
});

describe("script detection", () => {
  it("names languages its script gives away", () => {
    expect(scriptLanguage("कल मिलते हैं")).toBe("Hindi");
    expect(scriptLanguage("நாளை சந்திப்போம்")).toBe("Tamil");
    expect(scriptLanguage("see you tomorrow")).toBeNull();
  });
});

describe("parsing", () => {
  it("reads the model's JSON, even with prose around it", () => {
    const r = parseTranslation('Sure: {"detected":"Hindi","target":"English","translation":"See you tomorrow"}', req);
    expect(r).toEqual({ detected: "Hindi", target: "English", translation: "See you tomorrow" });
  });
  it("fills the direction when the model leaves it out", () => {
    const r = parseTranslation('{"detected":"English","translation":"कल मिलते हैं"}', req);
    expect(r?.target).toBe("Hindi");
  });
  it("refuses an empty translation", () => {
    expect(parseTranslation('{"detected":"English","translation":""}', req)).toBeNull();
  });
});

describe("languageName", () => {
  it("names a language the way the strip shows it", () => {
    expect(languageName("Hindi (Hinglish)")).toBe("Hindi");
    expect(languageName("Romanized Hindi")).toBe("Hindi");
    expect(languageName("Chinese (Simplified)")).toBe("Chinese");
    expect(languageName("spanish")).toBe("Spanish");
  });
});

describe("English or Hinglish, from the words", () => {
  it("tells romanised Hindi from English without a model", () => {
    expect(latinLanguage("kal milte hain office ke baad")).toBe("Hindi");
    expect(latinLanguage("bhai aaj shaam ko party hai aa jana")).toBe("Hindi");
    expect(latinLanguage("meeting kal 4 baje hai")).toBe("Hindi");
    expect(latinLanguage("see you after office tomorrow")).toBe("English");
    expect(latinLanguage("the meeting moved to 4 pm")).toBe("English");
  });

  it("leaves other languages, and too few words, to the model", () => {
    expect(latinLanguage("hola que tal")).toBeNull();
    expect(latinLanguage("bonjour mon ami")).toBeNull();
    expect(latinLanguage("ok")).toBeNull();
  });
});
