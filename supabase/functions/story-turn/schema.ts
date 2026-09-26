// `story-turn` request schema (docs/CONTRACTS.md §3): mode "turn", "title",
// "path" or "page". "path" and "page" (P-04) replace "turn", which stays only
// until the app has moved over.
import { z } from "npm:zod@3.23.8";
import {
  currentPageSchema,
  directionInputSchema,
  kidSchema,
  pageRefSchema,
  parentSettingsSchema,
  storyBibleSchema,
  storyBriefSchema,
  storyInputSchema,
  uuidSchema,
} from "../_shared/schemas.ts";

const turnRequestSchema = z.object({
  mode: z.literal("turn"),
  bookId: uuidSchema,
  kid: kidSchema,
  brief: storyBriefSchema,
  settings: parentSettingsSchema,
  bible: storyBibleSchema,
  pages: z.array(pageRefSchema).max(500).default([]),
  current: currentPageSchema,
  input: storyInputSchema,
});

const titleRequestSchema = z.object({
  mode: z.literal("title"),
  bookId: uuidSchema,
  kid: kidSchema,
  bible: storyBibleSchema,
  pages: z.array(pageRefSchema).max(500).default([]),
});

const pathIndexSchema = z.number().int().min(0);

const pathRequestSchema = z.object({
  mode: z.literal("path"),
  bookId: uuidSchema,
  kid: kidSchema,
  brief: storyBriefSchema,
  settings: parentSettingsSchema,
  bible: storyBibleSchema,
  pages: z.array(pageRefSchema).max(500).default([]),
  index: pathIndexSchema,
  // Absent/null at the very start (the brief alone drives the path); a direction otherwise.
  input: directionInputSchema.nullable().optional(),
});

const pageRequestSchema = z.object({
  mode: z.literal("page"),
  bookId: uuidSchema,
  kid: kidSchema,
  brief: storyBriefSchema,
  settings: parentSettingsSchema,
  bible: storyBibleSchema,
  pages: z.array(pageRefSchema).max(500).default([]),
  index: pathIndexSchema,
});

export const requestSchema = z.discriminatedUnion("mode", [
  turnRequestSchema,
  titleRequestSchema,
  pathRequestSchema,
  pageRequestSchema,
]);

export type TurnRequest = z.infer<typeof turnRequestSchema>;
export type TitleRequest = z.infer<typeof titleRequestSchema>;
export type PathRequest = z.infer<typeof pathRequestSchema>;
export type PageRequest = z.infer<typeof pageRequestSchema>;
