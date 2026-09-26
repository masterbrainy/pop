// `moderate` request schema (docs/CONTRACTS.md §3): either a text check or an
// image check, never both. Split out from index.ts so it's importable by
// tests without triggering that file's Deno.serve.
import { z } from "npm:zod@3.23.8";

export const textRequestSchema = z.object({ text: z.string().min(1).max(4000) });
export const imageRequestSchema = z.object({
  imageBase64: z.string().min(1),
  mimeType: z.string().min(1).max(100),
});
export const requestSchema = z.union([textRequestSchema, imageRequestSchema]);
