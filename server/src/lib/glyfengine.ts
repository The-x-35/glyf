import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { GlyfDef, GlyfDefSchema, GlyfStep } from "../schemas/glyfdef.js";
import { registryDir } from "./paths.js";
import { isPhoneTool, loadTools, phoneVar, runTool, toolExists } from "./tools.js";

/** Loads and executes Builder-format glyf definitions (§6.8).
 *  Executes llm · format · if · map · tool. `ask` steps resolve from
 *  caller-provided vars (a one-shot HTTP run can't pause mid-chain; the
 *  interactive ask UI ships with the chain editor, M9). */

export function loadRegistry(dir = registryDir("glyfs")): Map<string, GlyfDef> {
  const defs = new Map<string, GlyfDef>();
  for (const file of readdirSync(dir).filter(f => f.endsWith(".json")).sort()) {
    const raw = JSON.parse(readFileSync(join(dir, file), "utf8"));
    const def = GlyfDefSchema.parse(raw); // throws on any invalid def, incl. missing discloses
    if (defs.has(def.id)) throw new Error(`duplicate glyf id ${def.id} in ${file}`);
    defs.set(def.id, def);
  }
  return defs;
}

export type LLMComplete = (
  tier: "fast" | "smart",
  prompt: string,
  onToken: (t: string) => void,
) => Promise<string>;

export function interpolate(template: string, ctx: Record<string, string>): string {
  return template.replace(/\{\{([\w.]+)\}\}/g, (_, path: string) => lookup(ctx, path));
}

/** Dotted lookup into stringly ctx: `docs.0.title`, `docs.length` — values
 *  that hold JSON parse transparently. */
function lookup(ctx: Record<string, string>, path: string): string {
  const [head, ...rest] = path.split(".");
  let value: unknown = ctx[head];
  if (value === undefined) return "";
  for (const seg of rest) {
    if (typeof value === "string") {
      try { value = JSON.parse(value); } catch { return ""; }
    }
    if (seg === "length" && Array.isArray(value)) {
      value = value.length;
      continue;
    }
    if (value !== null && typeof value === "object") {
      value = (value as Record<string, unknown>)[seg];
    } else {
      return "";
    }
    if (value === undefined || value === null) return "";
  }
  return typeof value === "string" ? value : JSON.stringify(value);
}

/** Safe condition evaluator for `if` steps — NO eval. Supports:
 *  `A > B`, `>=`, `<`, `<=`, `==`, `!=`, `A contains B`, and bare truthiness
 *  (non-empty, non-"0", non-"false", non-"[]"). Operands are interpolated. */
export function evalCond(cond: string, ctx: Record<string, string>): boolean {
  const c = interpolate(cond, ctx).trim();
  const m = c.match(/^(.*?)\s*(>=|<=|==|!=|>|<|contains)\s*(.*)$/);
  if (!m) {
    return c !== "" && c !== "0" && c !== "false" && c !== "[]" && c !== "{}" && c !== "null";
  }
  const [, rawL, op, rawR] = m;
  const l = strip(rawL);
  const r = strip(rawR);
  const ln = Number(l);
  const rn = Number(r);
  const numeric = !Number.isNaN(ln) && !Number.isNaN(rn) && l !== "" && r !== "";
  switch (op) {
    case ">": return numeric && ln > rn;
    case "<": return numeric && ln < rn;
    case ">=": return numeric && ln >= rn;
    case "<=": return numeric && ln <= rn;
    case "==": return numeric ? ln === rn : l === r;
    case "!=": return numeric ? ln !== rn : l !== r;
    case "contains": return l.toLowerCase().includes(r.toLowerCase());
    default: return false;
  }
}

function strip(s: string): string {
  const t = s.trim();
  if ((t.startsWith("'") && t.endsWith("'")) || (t.startsWith('"') && t.endsWith('"'))) {
    return t.slice(1, -1);
  }
  return t;
}

export interface RunOptions {
  def: GlyfDef;
  input: string;
  vars: Record<string, string>;
  complete: LLMComplete;
  onToken: (t: string) => void;
  /** connectionId lookups for OAuth tools (M6); keyless tools ignore it. */
  connections?: Record<string, string>;
  /** A Builder try-out: a phone tool the app sent no answer for shows its
   *  sample instead (no Meet link is made to preview a glyf). */
  samples?: boolean;
}

/** Runs a glyf. Control flow: steps execute in order, EXCEPT steps that are
 *  referenced by any if/then/else or map — those run only when their branch
 *  activates. Streaming tokens are only emitted for the step feeding the
 *  declared output, so chains don't leak intermediates (§6.8). */
/** What to tell the person when a run fails. A tool's refusal and "needs
 *  input" are theirs to act on and pass through; everything else (a model
 *  that timed out, a provider that answered 503, a key that is missing) is
 *  ours, and the message says so without naming models or keys. */
export function userFacingRunError(err: unknown, fallback: string): string {
  const message = String((err as Error)?.message ?? err ?? "");
  if ((err as { userFacing?: boolean })?.userFacing === true) return message;
  return message.startsWith("needs input") || message.includes("tool") ? message : fallback;
}

export async function runGlyf(opts: RunOptions): Promise<string> {
  const { def, input, vars, complete, onToken } = opts;
  const ctx: Record<string, string> = { ...def.vars, ...vars, input };
  const byId = new Map(def.steps.map(s => [s.id, s]));
  const referenced = new Set<string>();
  for (const s of def.steps) {
    if (s.type === "if") { s.then.forEach(id => referenced.add(id)); s.else.forEach(id => referenced.add(id)); }
    if (s.type === "map") s.steps.forEach(id => referenced.add(id));
    if (s.type === "tool" && s.fallback) referenced.add(s.fallback);
  }

  /** The step whose words the person gets: the one the output reads from. */
  const streamingFinal = (out: string) => out === def.output.from;

  async function runStep(step: GlyfStep): Promise<void> {
    switch (step.type) {
      case "llm": {
        // Whatever a glyf asks, its words land in a message about to be sent.
        const prompt = interpolate(step.prompt, ctx) + (streamingFinal(step.out)
          ? "\n\nWrite it ready to send as it is: no placeholders like [Name], no subject line, no notes."
          : "");
        const streaming = step.out === def.output.from;
        const tier = step.model === "smart" || step.model === "strict" ? "smart" : "fast";
        const text = await complete(tier, prompt, streaming ? onToken : () => {});
        // Live models occasionally echo the [[directive]] prompt tag
        // (especially on empty input) — never let it reach the user.
        ctx[step.out] = text.trim().replace(/^(\s*\[\[[^\]]*\]\]\s*)+/, "").trim();
        break;
      }
      case "format": {
        ctx[step.out] = interpolate(step.template, ctx);
        break;
      }
      case "if": {
        const branch = evalCond(step.cond, ctx) ? step.then : step.else;
        for (const id of branch) {
          const target = byId.get(id);
          if (!target) throw new Error(`if step '${step.id}' references unknown step '${id}'`);
          await runStep(target);
        }
        break;
      }
      case "map": {
        let arr: unknown;
        try { arr = JSON.parse(ctx[step.over] ?? "[]"); } catch { arr = []; }
        if (!Array.isArray(arr)) arr = [arr];
        const results: string[] = [];
        for (const item of arr as unknown[]) {
          ctx.item = typeof item === "string" ? item : JSON.stringify(item);
          let last = "";
          for (const id of step.steps) {
            const target = byId.get(id);
            if (!target) throw new Error(`map step '${step.id}' references unknown step '${id}'`);
            await runStep(target);
            if ("out" in target) last = ctx[(target as { out: string }).out] ?? "";
          }
          results.push(last);
        }
        ctx[step.out] = JSON.stringify(results);
        break;
      }
      case "tool": {
        // §6.8/§11.5: tools resolve ONLY against the server-side registry —
        // user-authored glyfs can never make arbitrary HTTP calls.
        if (!toolExists(step.tool)) {
          throw new Error(`unknown tool '${step.tool}' — tools resolve against the registry only`);
        }
        // Answered on the phone: the keyboard sent it as phone.<tool>.
        if (isPhoneTool(step.tool)) {
          const meta = loadTools().get(step.tool)!;
          const sent = (ctx[phoneVar(step.tool)] ?? "").trim();
          const value = sent || (opts.samples ? meta.sample ?? "" : "");
          if (!value) {
            throw Object.assign(new Error(meta.connect ?? "Open this glyf from the Glyf keyboard"),
              { userFacing: true });
          }
          ctx[step.out] = value;
          break;
        }
        const args: Record<string, string> = {};
        for (const [k, v] of Object.entries(step.args)) {
          args[k] = interpolate(String(v), ctx);
        }
        try {
          ctx[step.out] = await runTool(step.tool, args, opts.connections ?? {});
        } catch (err) {
          // A try-out on a phone that hasn't turned it on (no location yet):
          // the sample shows what the glyf will write.
          const sample = opts.samples ? loadTools().get(step.tool)?.sample : undefined;
          if (sample && (err as { userFacing?: boolean })?.userFacing) {
            ctx[step.out] = sample;
            break;
          }
          // Its service down or silent: the step it names answers instead.
          const target = step.fallback ? byId.get(step.fallback) : undefined;
          if (!target) throw err;
          await runStep(target);
          if ("out" in target) ctx[step.out] = ctx[(target as { out: string }).out] ?? "";
        }
        break;
      }
      case "ask": {
        // One-shot runs can't pause; the answer must ride in as a var.
        if (ctx[step.out] === undefined || ctx[step.out] === "") {
          throw new Error(`needs input: ${interpolate(step.question, ctx)}`);
        }
        break;
      }
    }
  }

  for (const step of def.steps) {
    if (referenced.has(step.id)) continue; // branch-only steps
    await runStep(step);
  }

  const result = ctx[def.output.from];
  if (result === undefined) {
    throw new Error(`glyf ${def.id}: output.from '${def.output.from}' never produced`);
  }
  return result;
}
