// Turns a failed Gemini reply into a short reason, "402 STATUS: message", so a
// quota or billing refusal is visible in logs. Google's error body never
// carries the API key.

const MAX_MESSAGE = 200;

export function describeGeminiError(httpStatus: number, bodyText: string): string {
  try {
    const error = (JSON.parse(bodyText) as { error?: { status?: string; message?: string } }).error;
    if (!error?.message) return String(httpStatus);
    const message = error.message.length > MAX_MESSAGE ? `${error.message.slice(0, MAX_MESSAGE)}…` : error.message;
    return `${httpStatus} ${error.status ?? ""}: ${message}`.replace("  ", " ");
  } catch {
    return String(httpStatus);
  }
}

/** What the app may see: the HTTP status and Google's status word, never its message. */
export function geminiErrorCode(httpStatus: number, bodyText: string): string {
  try {
    const status = (JSON.parse(bodyText) as { error?: { status?: string } }).error?.status;
    return status ? `${httpStatus} ${status}` : String(httpStatus);
  } catch {
    return String(httpStatus);
  }
}
