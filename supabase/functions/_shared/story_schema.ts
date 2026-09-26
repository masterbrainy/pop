// story-turn's remaining model-call contracts: a strict JSON Schema for each
// OpenAI request, and a zod schema to re-validate the parsed response
// (defense in depth — strict mode can still be bypassed by a rewrite call).
//
// `mode: "turn"`'s STORY_TURN_JSON_SCHEMA/storyModelOutputSchema lived here
// too; they were removed with `mode: "turn"` (see _shared/story_path_schema.ts
// for `path`/`page`'s equivalents).
import { z } from "npm:zod@3.23.8";

export const TITLE_JSON_SCHEMA = {
  name: "pop_story_title",
  strict: true,
  schema: {
    type: "object",
    properties: { title: { type: "string" } },
    required: ["title"],
    additionalProperties: false,
  },
} as const;

export const titleModelOutputSchema = z.object({ title: z.string() });
export type TitleModelOutput = z.infer<typeof titleModelOutputSchema>;

export const RUBRIC_JSON_SCHEMA = {
  name: "pop_safety_rubric_verdict",
  strict: true,
  schema: {
    type: "object",
    properties: {
      safe: { type: "boolean" },
      reason: { type: "string" },
    },
    required: ["safe", "reason"],
    additionalProperties: false,
  },
} as const;

export const rubricModelOutputSchema = z.object({
  safe: z.boolean(),
  reason: z.string(),
});
