// `story-turn` request schema (docs/CONTRACTS.md §3): mode "title", "path" or
// "page". "path" and "page" (P-04) replace the old "turn" mode
// (append/new_page/revise_current), which was removed once the app moved
// over and the full eval passed on the new modes.
import { z } from "npm:zod@3.23.8";
import {
  directionInputSchema,
  kidSchema,
  pageRefSchema,
  parentSettingsSchema,
  storyBibleSchema,
  storyBriefSchema,
  uuidSchema,
} from "../_shared/schemas.ts";

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
  titleRequestSchema,
  pathRequestSchema,
  pageRequestSchema,
]);

export type TitleRequest = z.infer<typeof titleRequestSchema>;
export type PathRequest = z.infer<typeof pathRequestSchema>;
export type PageRequest = z.infer<typeof pageRequestSchema>;
