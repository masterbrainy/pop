// `tts` request schema (docs/CONTRACTS.md §3): text plus an optional voice.
import { z } from "npm:zod@3.23.8";

export const requestSchema = z.object({
  text: z.string().trim().min(1).max(2000),
  voice: z.string().trim().min(1).max(60).default("alloy"),
  // How to speak it (tone, pace), e.g. a warm bedtime storyteller for read-along.
  instructions: z.string().trim().min(1).max(1000).nullable().optional(),
});
