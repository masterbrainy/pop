// Structured, secret-safe server-side logging.
// NEVER pass secrets, tokens, or full user/story text into `extra` — counts,
// booleans, ids, durations and error messages only.

type LogFields = Record<string, string | number | boolean | null | undefined>;

function write(level: "info" | "error", context: string, fields?: LogFields) {
  console[level === "error" ? "error" : "log"](
    JSON.stringify({ level, context, ...fields }),
  );
}

export function logInfo(context: string, fields?: LogFields): void {
  write("info", context, fields);
}

export function logError(
  context: string,
  error: unknown,
  fields?: LogFields,
): void {
  const message = error instanceof Error ? error.message : String(error);
  write("error", context, { ...fields, message });
}
