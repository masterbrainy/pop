// Ties every function's entry point to one shape: CORS preflight, POST-only,
// the envelope on success, and PopError -> envelope on failure. Keeps each
// function's index.ts focused on its own request/response logic.
import { handlePreflight } from "./cors.ts";
import { errorResponse, okResponse } from "./envelope.ts";
import { isPopError } from "./errors.ts";
import { logError } from "./logger.ts";

export interface HandlerResult<T> {
  data: T;
  status?: number;
}

export type PopHandler<T> = (req: Request) => Promise<HandlerResult<T>>;

export async function servePop<T>(
  req: Request,
  functionName: string,
  handler: PopHandler<T>,
): Promise<Response> {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return errorResponse("bad_request", "Only POST is supported");
  }

  try {
    const { data, status } = await handler(req);
    return okResponse(data, status);
  } catch (error) {
    if (isPopError(error)) {
      if (error.code === "internal" || error.code === "upstream") {
        logError(functionName, error, { code: error.code });
      }
      return errorResponse(error.code, error.message);
    }
    logError(functionName, error, { code: "internal" });
    return errorResponse("internal", "Something went wrong. Please try again.");
  }
}
