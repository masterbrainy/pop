// The `story-turn` `path` and `page` modes' model contract (P-04,
// docs/CONTRACTS.md "story-turn modes path and page"): a strict JSON Schema
// for each OpenAI request, and a zod schema to re-validate the parsed
// response (defense in depth, same reasoning as story_schema.ts).
import { z } from "npm:zod@3.23.8";

const BIBLE_CHARACTER_JSON_SCHEMA = {
  type: "object",
  properties: {
    id: { type: "string" },
    name: { type: "string" },
    description: { type: "string" },
  },
  required: ["id", "name", "description"],
  additionalProperties: false,
} as const;

const bibleCharacterOutputSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
});

// `mode: "path"`: plans (or re-plans) the story path from `index` onward and
// writes page `index` itself in the same call.
export const STORY_PATH_JSON_SCHEMA = {
  name: "pop_story_path",
  strict: true,
  schema: {
    type: "object",
    properties: {
      // The path's beats from `index` onward ONLY — never beats before it.
      // The full new path is the kept earlier beats + this array.
      path: { type: "array", items: { type: "string" } },
      // True when `index` is the last beat of the full (kept + new) path.
      isEnding: { type: "boolean" },
      pageText: { type: "string" },
      artPrompt: { type: "string" },
      readingQuestion: { type: "string" },
      bibleTitle: { type: ["string", "null"] },
      bibleSetting: { type: "string" },
      bibleCharacters: { type: "array", items: BIBLE_CHARACTER_JSON_SCHEMA },
      bibleDirections: { type: "array", items: { type: "string" } },
      parentNote: { type: ["string", "null"] },
    },
    required: [
      "path",
      "isEnding",
      "pageText",
      "artPrompt",
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

export const storyPathModelOutputSchema = z.object({
  path: z.array(z.string()).min(1),
  isEnding: z.boolean(),
  pageText: z.string(),
  artPrompt: z.string(),
  readingQuestion: z.string().default(""),
  bibleTitle: z.string().nullable(),
  bibleSetting: z.string(),
  bibleCharacters: z.array(bibleCharacterOutputSchema),
  bibleDirections: z.array(z.string()),
  parentNote: z.string().nullable(),
});

export type StoryPathModelOutput = z.infer<typeof storyPathModelOutputSchema>;

// `mode: "page"`: writes page `index` from the existing `bible.path[index]`,
// with no re-planning — so no path or bible-update fields at all.
export const STORY_PAGE_JSON_SCHEMA = {
  name: "pop_story_page",
  strict: true,
  schema: {
    type: "object",
    properties: {
      pageText: { type: "string" },
      artPrompt: { type: "string" },
      readingQuestion: { type: "string" },
      parentNote: { type: ["string", "null"] },
    },
    required: ["pageText", "artPrompt", "readingQuestion", "parentNote"],
    additionalProperties: false,
  },
} as const;

export const storyPageModelOutputSchema = z.object({
  pageText: z.string(),
  artPrompt: z.string(),
  readingQuestion: z.string().default(""),
  parentNote: z.string().nullable(),
});

export type StoryPageModelOutput = z.infer<typeof storyPageModelOutputSchema>;
