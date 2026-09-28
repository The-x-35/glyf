import { z } from "zod";

/** §6.8 — the Builder format. Chaining + conditionals are first-class in the
 *  SCHEMA from day one (our differentiator); the M2 engine executes the
 *  llm/format subset and rejects the rest at runtime, not at parse time. */

export const StepSchema = z.discriminatedUnion("type", [
  z.object({
    id: z.string(),
    type: z.literal("llm"),
    prompt: z.string().min(1),
    model: z.enum(["fast", "smart", "strict"]).default("fast"),
    out: z.string(),
  }),
  z.object({
    id: z.string(),
    type: z.literal("format"),
    template: z.string(),
    out: z.string(),
  }),
  z.object({
    id: z.string(),
    type: z.literal("tool"),
    tool: z.string(),
    args: z.record(z.string(), z.unknown()).default({}),
    out: z.string(),
    /** A step to run instead when the tool can't answer (its service is
     *  down, say): Define asks the model when the dictionary is gone. */
    fallback: z.string().optional(),
  }),
  z.object({
    id: z.string(),
    type: z.literal("if"),
    cond: z.string(),
    then: z.array(z.string()),
    else: z.array(z.string()).default([]),
  }),
  z.object({
    id: z.string(),
    type: z.literal("map"),
    over: z.string(),
    steps: z.array(z.string()),
    out: z.string(),
  }),
  z.object({
    id: z.string(),
    type: z.literal("ask"),
    question: z.string(),
    out: z.string(),
  }),
]);

export const GlyfDefSchema = z.object({
  id: z.string().min(1),
  version: z.number().int().positive(),
  name: z.string().min(1),
  icon: z.string().default("sparkles"),
  input: z.enum(["field", "clipboard", "selection", "none"]),
  requires: z.object({
    fullAccess: z.boolean(),
    connectors: z.array(z.string()),
    wallet: z.boolean(),
  }),
  /** §6.8/§6.11: rendered verbatim before install. A glyf without a
   *  disclosure cannot ship — enforced here and by tests. */
  discloses: z.array(z.string().min(1)).min(1),
  vars: z.record(z.string(), z.string()).default({}),
  steps: z.array(StepSchema).min(1),
  output: z.object({
    mode: z.enum(["replace", "insert", "copy", "preview", "hud"]),
    from: z.string(),
  }),
});

export type GlyfDef = z.infer<typeof GlyfDefSchema>;
export type GlyfStep = z.infer<typeof StepSchema>;

export const RunRequestSchema = z.object({
  glyfId: z.string().min(1),
  input: z.string().max(8000).default(""),
  vars: z.record(z.string(), z.string()).default({}),
  deviceId: z.string().min(8).max(64),
  /** §6.16 — client-asserted until receipt validation (M7-ship TODO). */
  pro: z.boolean().default(false), // legacy client flag ⇒ treated as "plus"
  plan: z.enum(["free", "plus", "max"]).default("free"),
  /** Shareable vault details; a prompt opts in with {{profile}}. */
  profile: z.record(z.string().max(40), z.string().max(400)).optional(),
  /** The phone's coarse fix (the app's one, rounded); a tool step opts in
   *  with {{lat}}/{{lon}}. Never stored. */
  lat: z.number().min(-90).max(90).optional(),
  lon: z.number().min(-180).max(180).optional(),
});
export type RunRequest = z.infer<typeof RunRequestSchema>;
