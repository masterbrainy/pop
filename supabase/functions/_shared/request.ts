// Boundary validation shared by every function: parse JSON, then validate it
// against that function's zod schema, or fail fast with bad_request.
import type { ZodTypeAny } from "npm:zod@3.23.8";
import { PopError } from "./errors.ts";
import { zodIssueSummary } from "./schemas.ts";

export async function parseJsonBody(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw new PopError("bad_request", "Request body must be valid JSON");
  }
}

// `schema: ZodSchema<T>` (an alias for `ZodType<T, ZodTypeDef, T>`) would pin
// the schema's *input* type to T as well as its output type — wrong whenever
// a schema uses `.default(...)`, where input and output genuinely differ
// (e.g. tts's `voice`, or any `.array(...).default([])` field). Typing the
// schema parameter as the input-erased `ZodTypeAny` and inferring T only from
// its `_output` makes T resolve to the schema's *output* type, which is what
// `result.data` (and therefore every caller) actually receives.
export async function parseRequest<S extends ZodTypeAny>(
  req: Request,
  schema: S,
): Promise<S["_output"]> {
  const raw = await parseJsonBody(req);
  const result = schema.safeParse(raw);
  if (!result.success) {
    throw new PopError("bad_request", zodIssueSummary(result.error));
  }
  return result.data;
}
