import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import { GlyfDefSchema } from "../schemas/glyfdef.js";
import type { Guard } from "../lib/guard.js";
import { runGlyf, userFacingRunError } from "../lib/glyfengine.js";
import { completeStreaming } from "../providers/openrouter.js";
import { GlyfLibrary, SaveGlyfSchema, validateUserDef, ensureInputWired } from "../lib/userglyfs.js";

/** §6.8 — the Builder. Plain English → runnable Builder-format definition.
 *  Generation runs on the smart tier in STRICT mode: the model must return
 *  JSON that validates against the schema; one retry, then fail closed (§8.3). */

const GenerateSchema = z.object({
  description: z.string().min(4).max(600),
  deviceId: z.string().min(8).max(64),
});

const TestSchema = z.object({
  def: z.unknown(),
  input: z.string().max(4000).default(""),
  vars: z.record(z.string(), z.string()).default({}),
  deviceId: z.string().min(8).max(64),
});

const SYSTEM = `You design "glyfs" for an AI keyboard. A glyf is ONE bindable text action.
Return ONLY a JSON object (no markdown, no commentary) with EXACTLY this shape:
{
 "id": "user.draft",
 "version": 1,
 "name": "<2-4 word name>",
 "icon": "sparkles",
 "input": "field" | "clipboard" | "none",
 "requires": {"fullAccess": true, "connectors": [], "wallet": false},
 "discloses": ["<plain sentence: what user data this reads>"],
 "vars": {},
 "steps": [ ...1-4 steps... ],
 "output": {"mode": "preview", "from": "final"}
}
Step types you may use:
- {"id":"s1","type":"llm","model":"fast","prompt":"...","out":"x"} — prompt may use {{input}} and any var/out via {{name}}. The prompt MUST end with an instruction to reply with ONLY the resulting text.
- {"id":"s2","type":"format","template":"...{{x}}...","out":"y"}
- {"id":"s3","type":"if","cond":"{{x}} contains y","then":["s4"],"else":["s5"]} (branch steps listed by id)
- {"id":"s4","type":"tool","tool":"weather.now","args":{"place":"{{input}}"},"out":"w"} — ONLY these tools exist:
  weather.now(place), air.quality(place), quote.crypto(symbol), stocks.quote(symbol), fx.convert(amount,from,to),
  time.now(timezone), url.unfurl(url), wiki.summary(topic), dict.define(word), word.synonyms(word),
  places.search(query), route.eta(from,to), holidays.next(country), books.search(query), news.tech(),
  sports.next(team), recipes.search(dish), joke.random(), quote.inspire(), advice.random(), fact.random(),
  urban.define(term), country.info(country), repo.info(repo), food.info(food),
  calendar.today() [needs Google connected], notion.search(query) [needs Notion connected].
  Never invent tools.
The glyf runs inside a phone keyboard: what it writes goes straight into a chat message the person is typing. So every llm prompt must ask for text that is ready to send as it is: in the writer's own voice, about as long as their message (a short chat stays a short chat), never a formal email unless the glyf is about email, no subject line, no sign-off, and never placeholders like [Name] or [Date].
The LAST produced out must be named "final" (or output.from must point at it).
"input" should be "field" when the action transforms what the user typed, "clipboard" when it reacts to copied content, "none" when it needs no text.
Keep it minimal: most glyfs are ONE llm step.`;

export function builderRoutes(app: FastifyInstance, library: GlyfLibrary, guard: Guard): void {

  app.post("/builder/generate", async (req, reply) => {
    const parsed = GenerateSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const { description, deviceId } = parsed.data;
    const gate = await guard.spend(req, deviceId);
    if (!gate.ok) return reply.code(429).send({ error: gate.message });

    if (env.mockAI) {
      // Deterministic builder for tests/offline (§8.4).
      const def = {
        id: "user.draft", version: 1,
        name: mockName(description), icon: "sparkles",
        input: "field",
        requires: { fullAccess: true, connectors: [], wallet: false },
        discloses: ["the text in your current field"],
        vars: {},
        steps: [{
          id: "s1", type: "llm", model: "fast",
          prompt: `[[custom]]\n${description}. Apply this to the text below. Reply with ONLY the resulting text.\n\nText:\n{{input}}`,
          out: "final",
        }],
        output: { mode: "preview", from: "final" },
      };
      return { def };
    }

    // STRICT tier (§8.3): validate, retry once, fail closed.
    for (let attempt = 0; attempt < 2; attempt++) {
      let res: { text: string };
      try {
        res = await completeStreaming("smart", [
          { role: "system", content: SYSTEM },
          { role: "user", content: `Design a glyf: ${description}` },
        ], { onToken: () => {} });
      } catch (err) {
        req.log.warn({ attempt, err: String(err) }, "builder_models_unavailable");
        return reply.code(503).send({ error: "Couldn't make that glyf right now. Try again in a moment." });
      }
      const cleaned = res.text.trim()
        .replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
      try {
        const candidate = JSON.parse(cleaned);
        candidate.id = "user.draft";
        candidate.version = 1;
        // The model sometimes leaves out what the glyf reads (twice in a row
        // failed "Say no, politely"): it reads its input, which can be said
        // plainly instead of failing the build.
        if (!Array.isArray(candidate.discloses) || candidate.discloses.length === 0) {
          candidate.discloses = [candidate.input === "clipboard" ? "the text you copied"
            : candidate.input === "field" ? "the text in your current field" : "the text you run it on"];
        }
        const def = ensureInputWired(GlyfDefSchema.parse(candidate));
        const refusal = validateUserDef(def);
        if (refusal) throw new Error(refusal);
        req.log.info({ attempt, ok: true }, "builder_generated");
        return { def };
      } catch (err) {
        req.log.warn({ attempt, err: String(err) }, "builder_invalid");
      }
    }
    return reply.code(422).send({
      error: "Couldn't make a glyf from that. Try describing the action differently",
    });
  });

  app.post("/builder/test", async (req, reply) => {
    const parsed = TestSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const defParsed = GlyfDefSchema.safeParse(parsed.data.def);
    if (!defParsed.success) {
      return reply.code(422).send({ error: `Invalid glyf: ${defParsed.error.issues[0]?.message}` });
    }
    const refusal = validateUserDef(defParsed.data);
    if (refusal) return reply.code(422).send({ error: refusal });
    const gate = await guard.spend(req, parsed.data.deviceId);
    if (!gate.ok) return reply.code(429).send({ error: gate.message });

    const started = Date.now();
    try {
      const text = await runGlyf({
        def: defParsed.data,
        input: parsed.data.input,
        vars: parsed.data.vars,
        complete: async (tier, prompt, onToken) =>
          (await completeStreaming(tier, [{ role: "user", content: prompt }], { onToken })).text,
        onToken: () => {},
      });
      return { text, ms: Date.now() - started };
    } catch (err) {
      req.log.warn({ err: String((err as Error).message ?? err) }, "builder_test_failed");
      return reply.code(422).send({
        error: userFacingRunError(err, "Couldn't try it just now. Tap to try again."),
      });
    }
  });

  app.post("/glyfs", async (req, reply) => {
    const parsed = SaveGlyfSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const result = library.save(parsed.data.deviceId, parsed.data.def);
    if ("error" in result) return reply.code(422).send(result);
    return result;
  });

  app.get<{ Querystring: { deviceId: string } }>("/glyfs", async req => ({
    glyfs: library.mine(req.query.deviceId ?? "").map(g => ({
      id: g.def.id, name: g.def.name, icon: g.def.icon, input: g.def.input,
      discloses: g.def.discloses, version: g.def.version,
      published: g.published, updatedAt: g.updatedAt, def: g.def,
    })),
  }));

  app.delete<{ Params: { id: string }; Querystring: { deviceId: string } }>(
    "/glyfs/:id", async (req, reply) => {
      const ok = library.remove(req.query.deviceId ?? "", req.params.id);
      return ok ? { ok: true } : reply.code(404).send({ error: "not found" });
    });
}

function mockName(description: string): string {
  const words = description.split(/\s+/).filter(w => w.length > 2).slice(0, 3);
  const name = words.join(" ");
  return (name.charAt(0).toUpperCase() + name.slice(1)).slice(0, 28) || "My glyf";
}
