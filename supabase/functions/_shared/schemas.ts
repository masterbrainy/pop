// Shared zod schemas for the domain shapes in docs/CONTRACTS.md §1, reused
// across function request bodies. Validate at the boundary; never trust input.
import { z } from "npm:zod@3.23.8";
import { READING_LEVELS } from "./reading_levels.ts";

export const readingLevelSchema = z.enum(
  READING_LEVELS as unknown as [string, ...string[]],
);

export const uuidSchema = z.string().uuid();

export const kidSchema = z.object({
  firstName: z.string().trim().min(1).max(60),
  readingLevel: readingLevelSchema,
  interests: z.array(z.string().trim().min(1).max(60)).max(20).default([]),
});

// IMP-24 guided setup: a card's answer is a picture tile's id (turned into a
// phrase by setup_tiles.ts; an unknown id is ignored, never a bad_request, so
// a newer app never breaks an older server) or the family's own short words,
// typed or spoken (spoken answers get the real-harm check, brief_safety.ts).
export const briefAnswerSchema = z.union([
  z.object({ tile: z.string().trim().min(1).max(40) }).strict(),
  z.object({ text: z.string().trim().min(1).max(80), via: z.enum(["typed", "speech"]) }).strict(),
]);

export const MOODS = ["silly", "cosy", "brave"] as const;
export const PURPOSES = ["fun", "bedtime", "realMoment", "teach"] as const;

export const storyBriefSchema = z.object({
  interests: z.array(z.string().trim().min(1).max(60)).max(20).default([]),
  realMoment: z.string().trim().max(500).nullable().optional(),
  teach: z.string().trim().max(300).nullable().optional(),
  language: z.string().trim().min(2).max(10).default("en"),
  hero: briefAnswerSchema.nullable().optional(),
  place: briefAnswerSchema.nullable().optional(),
  problem: briefAnswerSchema.nullable().optional(),
  mood: z.enum(MOODS).nullable().optional(),
  purpose: z.enum(PURPOSES).nullable().optional(),
});

export const parentSettingsSchema = z.object({
  avoidTopics: z.array(z.string().trim().min(1).max(60)).max(30).default([]),
});

export const characterSchema = z.object({
  id: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(60),
  description: z.string().trim().min(1).max(500),
  referencePath: z.string().trim().min(1).max(300).nullable().optional(),
});

export const storyBibleSchema = z.object({
  title: z.string().trim().max(200).nullable().optional(),
  setting: z.string().trim().max(1000).default(""),
  characters: z.array(characterSchema).max(10).default([]),
  directions: z.array(z.string().trim().min(1).max(300)).max(100).default([]),
  // The story path (P-04, docs/CONTRACTS.md "story-turn modes path and page"):
  // one short beat per planned page, index 0 first. Optional and defaulting to
  // [] so a bible sent by an app build that predates the path stays valid.
  path: z.array(z.string().trim().max(300)).max(12).default([]),
});

export const pageRefSchema = z.object({
  index: z.number().int().min(0),
  text: z.string().max(2000),
});

/** IMP-25: a tapped choice's text is one short direction sentence. */
export const MAX_CHOICE_TEXT_CHARS = 120;

// The `path` and `page` modes' input (docs/CONTRACTS.md): a direction only,
// never "continue" (there's no page to continue — the path always has one).
// "choice" (IMP-25) is a tile the child tapped under a page's question.
export const directionInputSchema = z.object({
  kind: z.enum(["speech", "typed", "choice"]),
  speaker: z.enum(["parent", "kid"]),
  text: z.string().max(4000).default(""),
}).refine((input) => input.kind !== "choice" || input.text.trim().length <= MAX_CHOICE_TEXT_CHARS, {
  message: `A choice must be at most ${MAX_CHOICE_TEXT_CHARS} characters`,
  path: ["text"],
});

export type Kid = z.infer<typeof kidSchema>;
export type BriefAnswer = z.infer<typeof briefAnswerSchema>;
export type Mood = (typeof MOODS)[number];
export type Purpose = (typeof PURPOSES)[number];
export type StoryBrief = z.infer<typeof storyBriefSchema>;
export type ParentSettings = z.infer<typeof parentSettingsSchema>;
export type Character = z.infer<typeof characterSchema>;
export type StoryBible = z.infer<typeof storyBibleSchema>;
export type DirectionInput = z.infer<typeof directionInputSchema>;

/** Turns a ZodError into the single bad_request message our envelope wants. */
export function zodIssueSummary(error: z.ZodError): string {
  const first = error.issues[0];
  if (!first) return "Invalid request body";
  const path = first.path.join(".") || "(root)";
  return `${path}: ${first.message}`;
}
