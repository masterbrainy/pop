// The story-turn model's structured-output contract: a strict JSON Schema for
// the OpenAI request, and a zod schema to re-validate the parsed response
// (defense in depth — strict mode can still be bypassed by a rewrite call).
import { z } from "npm:zod@3.23.8";

export const STORY_TURN_JSON_SCHEMA = {
  name: "pop_story_turn",
  strict: true,
  schema: {
    type: "object",
    properties: {
      action: {
        type: "string",
        enum: ["append", "new_page", "revise_current", "none"],
      },
      pageText: { type: "string" },
      artPrompt: { type: "string" },
      breakSuggested: { type: "boolean" },
      readingQuestion: { type: "string" },
      bibleTitle: { type: ["string", "null"] },
      bibleSetting: { type: "string" },
      bibleCharacters: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
            description: { type: "string" },
          },
          required: ["id", "name", "description"],
          additionalProperties: false,
        },
      },
      bibleDirections: { type: "array", items: { type: "string" } },
      parentNote: { type: ["string", "null"] },
    },
    required: [
      "action",
      "pageText",
      "artPrompt",
      "breakSuggested",
      "readingQuestion",
      "bibleTitle",
      "bibleSetting",
      "bibleCharacters",
      "bibleDirections",
      "parentNote",
    ],
    additionalProperties: false,
  },
} as const;

export const storyModelOutputSchema = z.object({
  action: z.enum(["append", "new_page", "revise_current", "none"]),
  pageText: z.string(),
  artPrompt: z.string(),
  breakSuggested: z.boolean(),
  /** One question a parent can ask about this page (PRD C3); may be empty for "none". */
  readingQuestion: z.string().default(""),
  bibleTitle: z.string().nullable(),
  bibleSetting: z.string(),
  bibleCharacters: z.array(
    z.object({ id: z.string(), name: z.string(), description: z.string() }),
  ),
  bibleDirections: z.array(z.string()),
  parentNote: z.string().nullable(),
});

export type StoryModelOutput = z.infer<typeof storyModelOutputSchema>;

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
