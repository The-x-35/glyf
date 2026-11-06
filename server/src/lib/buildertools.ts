import type { GlyfDef } from "../schemas/glyfdef.js";
import { isPhoneTool, loadTools } from "./tools.js";

/**
 * The Builder's Tools: what a glyf may reach beyond the model, grouped the
 * way the app shows them (one switch each). A phone that sends `tools` with
 * /builder/generate gets glyfs that use only those; one that doesn't (every
 * build before this) gets the Builder exactly as it was.
 */

export interface BuilderConnection {
  id: string;
  /** Registry tools it opens up. */
  tools: string[];
  /** How the Builder's model is told about it. */
  prompt: string;
}

/** The keyless tools, as the Builder has always listed them. */
const LIVE_TOOLS = `weather.now(place), air.quality(place), quote.crypto(symbol), stocks.quote(symbol), fx.convert(amount,from,to),
  time.now(timezone), url.unfurl(url), wiki.summary(topic), dict.define(word), word.synonyms(word),
  places.search(query), maps.search(query), route.eta(from,to), holidays.next(country), books.search(query), news.tech(),
  sports.next(team), recipes.search(dish), joke.random(), quote.inspire(), advice.random(), fact.random(),
  urban.define(term), country.info(country), repo.info(repo), food.info(food)`;

export const BUILDER_CONNECTIONS: BuilderConnection[] = [
  {
    id: "meet",
    tools: ["meet.new"],
    prompt: `meet.new() — a NEW Google Meet link, made fresh on every run. args {}. Use it whenever the glyf sends a call, meeting or Meet link.`,
  },
  {
    id: "booking",
    tools: ["booking.link"],
    prompt: `booking.link() — the person's own booking page (Cal.com or Calendly). args {}. Use it whenever the glyf lets someone pick a time or book a slot.`,
  },
  {
    id: "calendar",
    tools: ["calendar.day"],
    prompt: `calendar.day() — today's events from their phone's calendar, one per line ("9:30 AM–10:00 AM Standup"). args {}. Use it for when they are busy or free today.`,
  },
  {
    id: "location",
    tools: ["place.here"],
    prompt: `place.here(lat,lon) — where they are now: the street, then a Google Maps link. ALWAYS args {"lat":"{{lat}}","lon":"{{lon}}"}. Use it whenever the glyf shares where they are.`,
  },
  {
    id: "details",
    tools: [],
    prompt: `{{profile}} — not a tool: a block of the writer's own saved details (name, email, phone, address, links), usable inside an llm prompt. Use it when the glyf needs their own details; never make details up.`,
  },
  {
    id: "live",
    tools: LIVE_TOOLS.match(/[a-z]+\.[a-z]+(?=\()/g) ?? [],
    prompt: `Live info tools (no login): ${LIVE_TOOLS}.`,
  },
];

const KNOWN = new Set(BUILDER_CONNECTIONS.map(c => c.id));

/** Only the ids this server knows, each once. */
export function cleanTools(tools: string[]): string[] {
  return [...new Set(tools.filter(t => KNOWN.has(t)))];
}

/** The tool section of the Builder's prompt for the switches that are on. */
export function toolSection(tools: string[]): string {
  const on = BUILDER_CONNECTIONS.filter(c => tools.includes(c.id));
  const steps = on.filter(c => c.tools.length > 0);
  const lines = [
    steps.length === 0
      ? `- No tool steps: this glyf has no tools turned on, so use only llm, format and if steps.`
      : `- {"id":"s4","type":"tool","tool":"meet.new","args":{},"out":"link"} — ONLY these tools are turned on for this glyf:`,
    ...on.map(c => `  ${c.prompt}`),
    `  Never invent tools, and never write a link, a time or a place yourself when a tool above gives it: put the tool's out in the text with {{name}}.`,
    `  A glyf that only hands over what a tool gives can be a tool step and a format step, with no llm step.`,
  ];
  return lines.join("\n");
}

/** Which switches a def uses, for the app to show as on. */
export function connectionsOf(def: GlyfDef): string[] {
  const used = new Set<string>();
  for (const s of def.steps) {
    if (s.type !== "tool") continue;
    const c = BUILDER_CONNECTIONS.find(c => c.tools.includes(s.tool));
    if (c) used.add(c.id);
  }
  if (/\{\{\s*profile\b/.test(JSON.stringify(def.steps))) used.add("details");
  return BUILDER_CONNECTIONS.map(c => c.id).filter(id => used.has(id));
}

/** A tool step outside the switches that are on, or null. */
export function outsideTools(def: GlyfDef, tools: string[]): string | null {
  const allowed = new Set(BUILDER_CONNECTIONS.filter(c => tools.includes(c.id)).flatMap(c => c.tools));
  for (const s of def.steps) {
    if (s.type === "tool" && !allowed.has(s.tool)) return s.tool;
  }
  if (!tools.includes("details") && /\{\{\s*profile\b/.test(JSON.stringify(def.steps))) return "profile";
  return null;
}

type Recipe = { name: string; icon: string; tool: string; args?: Record<string, string>;
  template?: string; prompt?: string; connection: string };

/**
 * The asks a glyf can answer with no model at all, made at once: a Meet link,
 * the booking link, where I am. Only short, plain asks — anything more ("…and
 * say I'm running late") goes to the model with the tools in its prompt.
 */
const RECIPES: { test: RegExp; recipe: Recipe }[] = [
  {
    test: /^(?:send|share|give|drop|paste|make|create|start|new)?\s*(?:me\s+)?(?:a\s+|my\s+)?(?:new\s+|fresh\s+)?(?:google\s+)?(?:meet|meeting|call|video\s*call|video)\s+link(?:\s+every\s+time)?$/i,
    recipe: { name: "New Meet link", icon: "video", tool: "meet.new", connection: "meet",
      template: "Join me on Google Meet: {{link}}" },
  },
  {
    test: /^(?:send|share|give|drop|paste)?\s*(?:me\s+)?(?:a\s+|my\s+)?(?:booking|scheduling|calendly|cal\.com|book\s+a\s+time)\s+(?:link|page)$/i,
    recipe: { name: "My booking link", icon: "calendar", tool: "booking.link", connection: "booking",
      template: "Pick a time that works for you: {{link}}" },
  },
  {
    test: /^(?:send|share|give|drop|tell\s+them)?\s*(?:my\s+)?(?:where\s+i\s+am|current\s+location|location|live\s+location|my\s+spot)(?:\s+now)?$/i,
    recipe: { name: "Where I am", icon: "map", tool: "place.here", connection: "location",
      args: { lat: "{{lat}}", lon: "{{lon}}" }, template: "I'm here: {{link}}" },
  },
  {
    test: /^(?:tell\s+(?:them|someone)|say|share|send)?\s*when\s+i(?:'|’)?m\s+free(?:\s+today)?$/i,
    recipe: { name: "When I'm free", icon: "calendar", tool: "calendar.day", connection: "calendar",
      prompt: "Here is my calendar for today, then when I have room:\n{{link}}\n\nWrite one short, friendly line I can send saying when I'm free today, using only those free times. Reply with ONLY the line." },
  },
];

export function recipeFor(description: string, tools: string[]): Record<string, unknown> | null {
  const ask = description.trim().replace(/[.!?]+$/, "").replace(/\s+/g, " ");
  const hit = RECIPES.find(r => r.test.test(ask) && tools.includes(r.recipe.connection));
  if (!hit) return null;
  const r = hit.recipe;
  const meta = loadTools().get(r.tool);
  return {
    id: "user.draft", version: 1, name: r.name, icon: r.icon,
    input: "none",
    requires: { fullAccess: true, connectors: [r.connection], wallet: false },
    discloses: [meta?.discloses ?? "nothing you type"],
    vars: {},
    steps: [
      { id: "s1", type: "tool", tool: r.tool, args: r.args ?? {}, out: "link" },
      r.prompt
        ? { id: "s2", type: "llm", model: "fast", prompt: r.prompt, out: "final" }
        : { id: "s2", type: "format", template: r.template, out: "final" },
    ],
    output: { mode: "preview", from: "final" },
  };
}

/** A run that calls no model and only hands over what the phone or a free
 *  lookup gave (a Meet link): it costs no run. */
export function modelFree(def: GlyfDef): boolean {
  return !def.steps.some(s => s.type === "llm")
    && def.steps.some(s => s.type === "tool" && (isPhoneTool(s.tool) || s.tool === "place.here"));
}
