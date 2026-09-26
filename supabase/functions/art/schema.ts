// `art` request schema (docs/CONTRACTS.md §3): which fields are required
// depends on `kind` — `page`/`plate`/`cutout` need a `pageIndex`,
// `character`/`cutout` need a `characterId`.
import { z } from "npm:zod@3.23.8";
import { characterSchema, uuidSchema } from "../_shared/schemas.ts";

const baseSchema = z.object({
  bookId: uuidSchema,
  kind: z.enum(["page", "cover", "character", "plate", "cutout"]),
  pageIndex: z.number().int().min(0).nullable().optional(),
  version: z.number().int().min(1),
  prompt: z.string().trim().min(1).max(2000),
  characters: z.array(characterSchema).max(10).default([]),
  characterId: z.string().trim().min(1).max(80).nullable().optional(),
});

export const requestSchema = baseSchema.superRefine((body, ctx) => {
  const needsPageIndex = body.kind === "page" || body.kind === "plate" || body.kind === "cutout";
  if (needsPageIndex && (body.pageIndex === null || body.pageIndex === undefined)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["pageIndex"],
      message: `pageIndex is required for art kind "${body.kind}"`,
    });
  }
  const needsCharacterId = body.kind === "character" || body.kind === "cutout";
  if (needsCharacterId && (body.characterId === null || body.characterId === undefined)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["characterId"],
      message: `characterId is required for art kind "${body.kind}"`,
    });
  }
});

export type ArtRequest = z.infer<typeof baseSchema>;
