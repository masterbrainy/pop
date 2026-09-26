// `moderate` request schema (docs/CONTRACTS.md §3): either a text check or an
// image check, never both. Split out from index.ts so it's importable by
// tests without triggering that file's Deno.serve.
import { z } from "npm:zod@3.23.8";

// A 512-px JPEG frame or a 1.5 MB drawing is roughly 2.1 MB of base64; 3,000,000
// characters leaves headroom without letting a signed-in user post an unbounded
// body (R-32).
const MAX_IMAGE_BASE64_LENGTH = 3_000_000;

export const textRequestSchema = z.object({ text: z.string().min(1).max(4000) });
export const imageRequestSchema = z.object({
  imageBase64: z.string().min(1).max(MAX_IMAGE_BASE64_LENGTH),
  mimeType: z.string().min(1).max(100),
});
export const requestSchema = z.union([textRequestSchema, imageRequestSchema]);
