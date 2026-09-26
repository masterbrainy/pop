// `story-turn` request schema (docs/CONTRACTS.md §3): mode "turn" or "title".
import { z } from "npm:zod@3.23.8";
import {
  currentPageSchema,
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

export const requestSchema = z.discriminatedUnion("mode", [
  turnRequestSchema,
  titleRequestSchema,
]);

export type TurnRequest = z.infer<typeof turnRequestSchema>;
export type TitleRequest = z.infer<typeof titleRequestSchema>;
