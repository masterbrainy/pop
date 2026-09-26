// Retries an upstream call that failed for a passing reason: the provider's
// quota or billing check (402, 429) or a server error (5xx), or a dropped
// connection. A request the provider rejected as bad (other 4xx) is not retried.

export const RETRY_STATUSES = new Set([402, 429, 500, 502, 503, 504]);

/** Waits before each retry: three retries over about 17 s, since a 402 burst can outlast 5 s. */
export const DEFAULT_RETRY_DELAYS_MS = [2_000, 5_000, 10_000];

export interface RetryOptions {
  delaysMs?: number[];
  sleep?: (ms: number) => Promise<void>;
}

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function fetchWithRetry(
  fetcher: () => Promise<Response>,
  { delaysMs = DEFAULT_RETRY_DELAYS_MS, sleep = wait }: RetryOptions = {},
): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    const isLast = attempt >= delaysMs.length;
    try {
      const res = await fetcher();
      if (res.ok || isLast || !RETRY_STATUSES.has(res.status)) return res;
      await res.body?.cancel();
    } catch (error) {
      if (isLast) throw error;
    }
    await sleep(delaysMs[attempt]);
  }
}
