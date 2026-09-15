// GENERATED from shared/contracts — do not edit (tools/gen_contracts.mjs)
import { z } from "zod";

export const IntentOriginSchema = z.object({
  source: z.enum(["typed", "clipboard", "glyf"]),
  glyfId: z.string().nullable(),
  rawText: z.string(),
});

export const IntentRiskSchema = z.object({
  score: z.number(),
  flags: z.array(z.string()),
});

export const IntentSchema = z.object({
  id: z.string(),
  version: z.number().int(),
  createdAt: z.string(),
  expiresAt: z.string(),
  kind: z.enum(["swap", "send", "sign_message", "dictation"]),
  origin: IntentOriginSchema,
  payload: z.record(z.string(), z.string()),
  risk: IntentRiskSchema,
  nonce: z.string(),
});

export const ResultErrorSchema = z.object({
  code: z.string(),
  message: z.string(),
});

export const ResultSchema = z.object({
  intentId: z.string(),
  status: z.enum(["success", "rejected", "failed", "expired"]),
  payload: z.record(z.string(), z.string()),
  error: ResultErrorSchema.nullable(),
  completedAt: z.string(),
});
