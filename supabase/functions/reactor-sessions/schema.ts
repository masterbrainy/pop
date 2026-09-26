// `reactor-sessions` request schema (docs/CONTRACTS.md §3): admin-only list/kill.
import { z } from "npm:zod@3.23.8";

export const requestSchema = z.object({ action: z.enum(["list", "kill"]) });
