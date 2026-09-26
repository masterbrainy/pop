// `tts` request schema (docs/CONTRACTS.md §3): text plus an optional voice.
import { z } from "npm:zod@3.23.8";

export const requestSchema = z.object({
  text: z.string().trim().min(1).max(2000),
  voice: z.string().trim().min(1).max(60).default("alloy"),
});
