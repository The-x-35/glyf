import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { runGlyf } from "../src/lib/glyfengine.js";
import { GlyfDefSchema } from "../src/schemas/glyfdef.js";
import { builderSystem } from "../src/routes/builder.js";
import { connectionsOf, modelFree, outsideTools, recipeFor, toolSection } from "../src/lib/buildertools.js";
import { phoneToolsOf } from "../src/lib/tools.js";
import { validateUserDef } from "../src/lib/userglyfs.js";

/** The Builder's Tools: switches that say what a glyf may use, phone tools
 *  the keyboard answers (a new Meet link each run), and a glyf's own Private
 *  AI choice. Phones that send none of it get the Builder as it was. */

process.env.MOCK_AI = "true";
beforeAll(() => { env.mockAI = true; });

const noLLM = async () => { throw new Error("no model expected"); };

describe("builder tools", () => {
  it("makes 'send a Meet link' with no model: a phone tool, then the line", () => {
    const def = GlyfDefSchema.parse(recipeFor("Send my meeting link", ["meet"]));
    expect(def.steps.map(s => s.type)).toEqual(["tool", "format"]);
    expect(phoneToolsOf(def.steps)).toEqual(["meet.new"]);
    expect(def.requires.connectors).toEqual(["meet"]);
    expect(validateUserDef(def)).toBeNull();
    expect(modelFree(def)).toBe(true);
    // The switch is off: no recipe, the model decides with what is on.
    expect(recipeFor("Send my meeting link", ["live"])).toBeNull();
    // More than the link: the model writes it, with the tool in its prompt.
    expect(recipeFor("send a meet link and say I'm 5 min late", ["meet"])).toBeNull();
  });

  it("knows the booking link and where I am", () => {
    expect(recipeFor("share my booking link", ["booking"])).toMatchObject({ name: "My booking link" });
    const here = GlyfDefSchema.parse(recipeFor("where I am", ["location"]));
    expect(here.steps[0]).toMatchObject({ tool: "place.here", args: { lat: "{{lat}}", lon: "{{lon}}" } });
  });

  it("runs a phone tool from the var the keyboard sent, and says where to turn it on without one", async () => {
    const def = GlyfDefSchema.parse(recipeFor("new meet link every time", ["meet"]));
    const text = await runGlyf({ def, input: "", vars: { "phone.meet.new": "https://meet.google.com/aaa-bbbb-ccc" },
      complete: noLLM, onToken: () => {} });
    expect(text).toBe("Join me on Google Meet: https://meet.google.com/aaa-bbbb-ccc");
    await expect(runGlyf({ def, input: "", vars: {}, complete: noLLM, onToken: () => {} }))
      .rejects.toThrow("Connect Google Meet in Glyf › Connected tools");
    // A Builder try-out shows the sample instead of making a link.
    const tried = await runGlyf({ def, input: "", vars: {}, samples: true, complete: noLLM, onToken: () => {} });
    expect(tried).toContain("meet.google.com/");
  });

  it("tells the model only about the switches that are on, and catches a glyf that strays", () => {
    const meetOnly = builderSystem(["meet"]);
    expect(meetOnly).toContain("meet.new()");
    expect(meetOnly).not.toContain("weather.now(place)");
    expect(meetOnly).not.toContain("notion.search");
    expect(toolSection([])).toContain("No tool steps");
    // No tools sent at all: the prompt every earlier build got.
    expect(builderSystem()).toContain("calendar.today() [needs Google connected]");
    const weather = GlyfDefSchema.parse({
      id: "user.draft", version: 1, name: "w", input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false }, discloses: ["x"],
      steps: [{ id: "s1", type: "tool", tool: "weather.now", args: { place: "{{input}}" }, out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    expect(outsideTools(weather, ["meet"])).toBe("weather.now");
    expect(outsideTools(weather, ["live"])).toBeNull();
    expect(connectionsOf(weather)).toEqual(["live"]);
  });
});

describe("builder routes with tools", () => {
  it("generate hands back the recipe with its switches and the glyf's Private AI choice", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/builder/generate",
      payload: { description: "Send my meeting link", deviceId: "tools-dev-0000001", tools: ["meet", "live"], privateAI: false },
    });
    expect(res.statusCode).toBe(200);
    const def = res.json().def;
    expect(def.name).toBe("New Meet link");
    expect(def.requires.connectors).toEqual(["meet"]);
    expect(def.privateAI).toBe(false);

    // Saved and run from the keyboard with the link it made on the phone.
    const save = await app.inject({ method: "POST", url: "/glyfs", payload: { deviceId: "tools-dev-0000001", def } });
    const id = save.json().id;
    const run = await app.inject({
      method: "POST", url: "/glyf/run",
      payload: { glyfId: id, input: "", vars: { "phone.meet.new": "https://meet.google.com/xyz-abcd-efg" }, deviceId: "tools-dev-0000001" },
    });
    expect(run.payload).toContain("Join me on Google Meet: https://meet.google.com/xyz-abcd-efg");
    expect(run.payload).toContain("event: done");
    // No model ran, so no run was spent.
    expect(run.payload).not.toContain("remaining");
  });

  it("an old phone's generate is unchanged (no tools field, no privateAI, no recipe)", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/builder/generate",
      payload: { description: "Send my meeting link", deviceId: "tools-dev-0000002" },
    });
    const def = res.json().def;
    expect(def.steps[0].type).toBe("llm");
    expect(def.privateAI).toBeUndefined();
  });

  it("the try-out shows samples for phone tools and the location it was given", async () => {
    const app = signedInApp();
    const gen = await app.inject({
      method: "POST", url: "/builder/generate",
      payload: { description: "where I am", deviceId: "tools-dev-0000003", tools: ["location"] },
    });
    const def = gen.json().def;
    const withFix = await app.inject({
      method: "POST", url: "/builder/test",
      payload: { def, input: "", vars: { lat: "37.7897", lon: "-122.4" }, deviceId: "tools-dev-0000003" },
    });
    expect(withFix.json().text).toContain("query=37.7897,-122.4");
    const without = await app.inject({
      method: "POST", url: "/builder/test",
      payload: { def, input: "", vars: {}, deviceId: "tools-dev-0000003" },
    });
    expect(without.json().text).toContain("I'm here: Near");
  });
});

describe("free today", () => {
  it("reads the day on the phone and has the model say when", async () => {
    const def = GlyfDefSchema.parse(recipeFor("Tell them when I’m free today", ["calendar"]));
    expect(phoneToolsOf(def.steps)).toEqual(["calendar.day"]);
    expect(modelFree(def)).toBe(false);
    let asked = "";
    const text = await runGlyf({ def, input: "", vars: { "phone.calendar.day": "3:00–4:00 PM Gym\nI'm free Fri 6 Nov, 4:00–9:00 PM" },
      complete: async (_t, prompt) => { asked = prompt; return "Free after 4 today!"; }, onToken: () => {} });
    expect(asked).toContain("4:00–9:00 PM");
    expect(text).toBe("Free after 4 today!");
  });
});
