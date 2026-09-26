// `stt-token` request schema (docs/CONTRACTS.md §3): an empty body, strictly.
import { z } from "npm:zod@3.23.8";

export const requestSchema = z.object({}).strict();
