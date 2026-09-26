// Retries an upstream call that failed for a passing reason: the provider's
// quota or billing check (402, 429) or a server error (5xx), or a dropped
// connection. A request the provider rejected as bad (other 4xx) is not retried.
// Every attempt can carry a deadline, so a hung provider fails fast instead of
// holding the app on "Painting…" (IMP-10). A timed-out attempt is not retried:
// the deadline is meant to bound the whole call.
import { PopError } from "./errors.ts";

export const RETRY_STATUSES = new Set([402, 429, 500, 502, 503, 504]);

/** Waits before each retry: three retries over about 17 s, since a 402 burst can outlast 5 s. */
export const DEFAULT_RETRY_DELAYS_MS = [2_000, 5_000, 10_000];

/** Per-attempt deadlines for each upstream, sized from BUILD_LOG's measured p90s. */
export const UPSTREAM_TIMEOUTS_MS = {
  chat: 12_000,
  moderation: 3_500,
  geminiText: 10_000,
  geminiImage: 25_000,
} as const;

export type Fetcher = (signal?: AbortSignal) => Promise<Response>;

export interface RetryOptions {
  delaysMs?: number[];
  sleep?: (ms: number) => Promise<void>;
  /** Aborts each attempt after this long and throws an `upstream` PopError. */
  timeoutMs?: number;
  /** Names the call in the timeout error, e.g. "Model request". */
  label?: string;
  retryStatuses?: ReadonlySet<number>;
}

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function isTimeout(error: unknown): boolean {
  return error instanceof DOMException && (error.name === "TimeoutError" || error.name === "AbortError");
}

export async function fetchWithRetry(
  fetcher: Fetcher,
  {
    delaysMs = DEFAULT_RETRY_DELAYS_MS,
    sleep = wait,
    timeoutMs,
    label = "Upstream request",
    retryStatuses = RETRY_STATUSES,
  }: RetryOptions = {},
): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    const isLast = attempt >= delaysMs.length;
    try {
      const res = await fetcher(timeoutMs === undefined ? undefined : AbortSignal.timeout(timeoutMs));
      if (res.ok || isLast || !retryStatuses.has(res.status)) return res;
      await res.body?.cancel();
    } catch (error) {
      if (isTimeout(error)) throw new PopError("upstream", `${label} timed out`);
      if (isLast) throw error;
    }
    await sleep(delaysMs[attempt]);
  }
}

/** 429 and 5xx: the provider is busy or broken for a moment. 402 (billing) won't clear in a second. */
export const ONE_RETRY_STATUSES = new Set([429, 500, 502, 503, 504]);

/** A retry wait between 250 and 750 ms, so parallel calls that failed together don't retry together. */
export function jitteredDelayMs(random: number): number {
  return Math.floor(250 + 500 * random);
}

export interface OneRetryOptions {
  timeoutMs: number;
  label: string;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}

/** One deadline-bound attempt, plus one jittered retry on 429/5xx or a dropped connection. */
export function fetchWithOneRetry(
  fetcher: Fetcher,
  { timeoutMs, label, sleep = wait, random = Math.random }: OneRetryOptions,
): Promise<Response> {
  return fetchWithRetry(fetcher, {
    delaysMs: [jitteredDelayMs(random())],
    sleep,
    timeoutMs,
    label,
    retryStatuses: ONE_RETRY_STATUSES,
  });
}
