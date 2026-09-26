// `motion-prompt` request schema (docs/CONTRACTS.md §3).
import { z } from "npm:zod@3.23.8";
import { uuidSchema } from "../_shared/schemas.ts";

export const requestSchema = z.object({
  bookId: uuidSchema,
  pageIndex: z.number().int().min(0),
  text: z.string().trim().min(1).max(2000),
  stillPath: z.string().trim().min(1).max(300),
});
