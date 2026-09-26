// `reactor-token` request schema (docs/CONTRACTS.md §3): mint / report / cleanup.
import { z } from "npm:zod@3.23.8";

export const requestSchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("mint") }),
  z.object({ action: z.literal("report"), sessionId: z.string().trim().min(1).max(200) }),
  z.object({ action: z.literal("cleanup") }),
]);
