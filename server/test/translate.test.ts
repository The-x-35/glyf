import { describe, expect, it } from "vitest";
import { chooseTarget, parseTranslation, scriptLanguage } from "../src/lib/translate.js";

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
