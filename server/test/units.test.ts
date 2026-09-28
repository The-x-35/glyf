import { describe, expect, it } from "vitest";
import { convertUnits } from "../src/lib/units.js";
import { planByRules } from "../src/lib/act.js";
import { instantAnswer } from "../src/lib/answers.js";

/** The same cases as UnitsTest.kt and GlyfEngineTests.testUnitsConvertOnThePhone:
 *  all three convert alike. */
const CASES: Array<[string, string]> = [
  ["5 km in miles", "5 km is 3.107 miles"],
  ["convert 100 miles to km", "100 miles is 160.9 km"],
  ["100 miles to m", "100 miles is 160,934 m"],
  ["what is 6 ft in cm", "6 feet is 182.9 cm"],
  ["5 in in cm", "5 inches is 12.7 cm"],
  ["how many cm in an inch", "1 inch is 2.54 cm"],
  ["how many feet in a mile?", "1 mile is 5,280 feet"],
  ["100f to c", "100°F is 37.78°C"],
  ["37 c in f", "37°C is 98.6°F"],
  ["-40 celsius to fahrenheit", "-40°C is -40°F"],
  ["70 kg in lbs", "70 kg is 154.3 lb"],
  ["5 pounds in kg", "5 lb is 2.268 kg"],
  ["2 cups in ml", "2 cups is 473.2 ml"],
  ["how many ml are in 2 cups", "2 cups is 473.2 ml"],
  ["1 gallon to liters", "1 gallon is 3.785 litres"],
  ["60 mph in km/h", "60 mph is 96.56 km/h"],
  ["3 hours in minutes", "3 hours is 180 minutes"],
  ["1 acre in sq ft", "1 acre is 43,560 sq ft"],
  ["5 feet 10 inches in cm", "5 ft 10 in is 177.8 cm"],
  ["5'10 in cm", "5 ft 10 in is 177.8 cm"],
  ["178 cm in feet", "178 cm is 5 ft 10 in"],
  ["2 m in ft", "2 m is 6 ft 7 in"],
  ["100 m in feet", "100 m is 328.1 feet"],
];

describe("unit conversions", () => {
  it("converts what people ask, the way they ask it", () => {
    for (const [asked, said] of CASES) expect(convertUnits(asked)?.say, asked).toBe(said);
  });

  it("leaves alone what is not a conversion", () => {
    for (const text of ["5 pounds in dollars", "5 k in miles", "meet in 5 min", "i have 2 hours in the office",
      "5 km", "km to miles", "5 kg in km"]) {
      expect(convertUnits(text), text).toBeNull();
    }
  });

  it("works out a tip, and the days until a day everyone counts to", async () => {
    expect(planByRules("15% tip on 64")).toEqual({ intent: "answer", query: "15% tip on 64" });
    expect((await instantAnswer("15% tip on 64"))?.say).toBe("15% tip on 64 is 9.60 (73.60 in all)");
    for (const asked of ["how many days until christmas", "days till new years", "how long until halloween?",
      "how many days until dec 25", "how many weeks until thanksgiving"]) {
      expect(planByRules(asked)?.intent, asked).toBe("answer");
      const card = await instantAnswer(asked, { tz: "America/New_York" });
      expect(card?.id, asked).toBe("days");
      expect(card?.say, asked).toMatch(/^(\d+ (days?|weeks?)( and \d+ days?)? until |.+ is today$)/);
    }
    expect(planByRules("how long until the bus comes")?.intent).not.toBe("answer");
  });

  it("is an answer worked out here, never a model's", async () => {
    expect(planByRules("5 km in miles")).toEqual({ intent: "answer", query: "5 km in miles" });
    const card = await instantAnswer("5 km in miles");
    expect(card).toMatchObject({ kind: "answer", id: "units", value: "3.107 miles", say: "5 km is 3.107 miles" });
  });
});
