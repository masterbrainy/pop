// The one response envelope every Pop! server function uses (docs/CONTRACTS.md §3).
import { CORS_HEADERS } from "./cors.ts";

export type ErrorCode =
  | "unauthorized"
  | "forbidden"
  | "rate_limited"
  | "bad_request"
  | "unsafe"
  | "upstream"
  | "internal";

export interface OkEnvelope<T> {
  ok: true;
  data: T;
}

export interface ErrEnvelope {
  ok: false;
  error: { code: ErrorCode; message: string };
}

// CONTRACTS.md says "the HTTP status matches" the envelope without pinning exact
// codes. This is the simplest reading: each error code gets one conventional
// HTTP status, applied consistently across every function.
const STATUS_BY_CODE: Record<ErrorCode, number> = {
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  unsafe: 422,
  rate_limited: 429,
  upstream: 502,
  internal: 500,
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

export function okResponse<T>(data: T, status = 200): Response {
  const body: OkEnvelope<T> = { ok: true, data };
  return jsonResponse(body, status);
}

export function errorResponse(code: ErrorCode, message: string): Response {
  const body: ErrEnvelope = { ok: false, error: { code, message } };
  return jsonResponse(body, STATUS_BY_CODE[code]);
}

export function statusForCode(code: ErrorCode): number {
  return STATUS_BY_CODE[code];
}
