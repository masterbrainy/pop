// `art` request schema (docs/CONTRACTS.md §3): which fields are required
// depends on `kind` — `page`/`plate`/`cutout` need a `pageIndex`,
// `character`/`cutout`/`drawing` need a `characterId`, and `drawing` alone
// needs a `drawing` (the kid's own finger drawing, base64 PNG or JPEG).
import { decodeBase64 } from "jsr:@std/encoding@1/base64";
import { z } from "npm:zod@3.23.8";
import { sniffImageMimeType } from "../_shared/image_format.ts";
import { characterSchema, uuidSchema } from "../_shared/schemas.ts";

// ~1.5 MB decoded (task spec): a kid's finger drawing, not a photo.
export const MAX_DRAWING_BYTES = 1_572_864;
// Coarse guard on the base64 *string* itself, applied before decoding, so an
// oversized payload is rejected without ever base64-decoding it. Base64
// inflates size by ~4/3, so this comfortably covers MAX_DRAWING_BYTES.
const MAX_DRAWING_BASE64_LENGTH = 2_500_000;

const baseSchema = z.object({
  bookId: uuidSchema,
  kind: z.enum(["page", "cover", "character", "plate", "cutout", "drawing"]),
  pageIndex: z.number().int().min(0).nullable().optional(),
  version: z.number().int().min(1),
  prompt: z.string().trim().min(1).max(2000),
  characters: z.array(characterSchema).max(10).default([]),
  characterId: z.string().trim().min(1).max(80).nullable().optional(),
  drawing: z.string().trim().min(1).max(MAX_DRAWING_BASE64_LENGTH).nullable().optional(),
});

/** `null` for invalid base64, so schema validation can fail with a clean message instead of throwing. */
function decodeDrawingBytes(value: string): Uint8Array | null {
  try {
    return decodeBase64(value);
  } catch {
    return null;
  }
}

export const requestSchema = baseSchema.superRefine((body, ctx) => {
  const needsPageIndex = body.kind === "page" || body.kind === "plate" || body.kind === "cutout";
  if (needsPageIndex && (body.pageIndex === null || body.pageIndex === undefined)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["pageIndex"],
      message: `pageIndex is required for art kind "${body.kind}"`,
    });
  }
  const needsCharacterId = body.kind === "character" || body.kind === "cutout" || body.kind === "drawing";
  if (needsCharacterId && (body.characterId === null || body.characterId === undefined)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["characterId"],
      message: `characterId is required for art kind "${body.kind}"`,
    });
  }

  if (body.kind !== "drawing") return;

  if (body.drawing === null || body.drawing === undefined) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["drawing"],
      message: `drawing is required for art kind "drawing"`,
    });
    return;
  }

  const bytes = decodeDrawingBytes(body.drawing);
  if (!bytes) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["drawing"], message: "drawing must be valid base64" });
    return;
  }
  if (bytes.length > MAX_DRAWING_BYTES) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["drawing"],
      message: `drawing must be at most ${MAX_DRAWING_BYTES} bytes decoded`,
    });
    return;
  }
  if (!sniffImageMimeType(bytes)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["drawing"], message: "drawing must be a PNG or JPEG image" });
  }
});

export type ArtRequest = z.infer<typeof baseSchema>;
