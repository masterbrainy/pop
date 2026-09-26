import type { ErrorCode } from "./envelope.ts";

/** Thrown anywhere in a function's logic; the handler wrapper turns it into the envelope. */
export class PopError extends Error {
  readonly code: ErrorCode;

  constructor(code: ErrorCode, message: string) {
    super(message);
    this.name = "PopError";
    this.code = code;
  }
}

export function isPopError(value: unknown): value is PopError {
  return value instanceof PopError;
}
