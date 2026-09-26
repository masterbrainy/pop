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

export const storyBriefSchema = z.object({
  interests: z.array(z.string().trim().min(1).max(60)).max(20).default([]),
  realMoment: z.string().trim().max(500).nullable().optional(),
  teach: z.string().trim().max(300).nullable().optional(),
  language: z.string().trim().min(2).max(10).default("en"),
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
});

export const pageRefSchema = z.object({
  index: z.number().int().min(0),
  text: z.string().max(2000),
});

export const currentPageSchema = z.object({
  index: z.number().int().min(0),
  text: z.string().max(2000).default(""),
});

export const storyInputSchema = z.object({
  kind: z.enum(["speech", "typed", "continue"]),
  speaker: z.enum(["parent", "kid"]),
  text: z.string().max(4000).default(""),
});

export type Kid = z.infer<typeof kidSchema>;
export type StoryBrief = z.infer<typeof storyBriefSchema>;
export type ParentSettings = z.infer<typeof parentSettingsSchema>;
export type Character = z.infer<typeof characterSchema>;
export type StoryBible = z.infer<typeof storyBibleSchema>;
export type StoryInput = z.infer<typeof storyInputSchema>;

/** Turns a ZodError into the single bad_request message our envelope wants. */
export function zodIssueSummary(error: z.ZodError): string {
  const first = error.issues[0];
  if (!first) return "Invalid request body";
  const path = first.path.join(".") || "(root)";
  return `${path}: ${first.message}`;
}
