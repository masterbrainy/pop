import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { fetchWithOneRetry, fetchWithRetry, jitteredDelayMs, RETRY_STATUSES } from "./retry.ts";
import { PopError } from "./errors.ts";

function responses(...statuses: number[]) {
  let call = 0;
  const fetcher = () => Promise.resolve(new Response("{}", { status: statuses[Math.min(call++, statuses.length - 1)] }));
  return { fetcher, calls: () => call };
}

Deno.test("fetchWithRetry returns the first good response without retrying", async () => {
  const { fetcher, calls } = responses(200);
  const res = await fetchWithRetry(fetcher, { delaysMs: [1, 1], sleep: () => Promise.resolve() });
  assertEquals(res.status, 200);
  assertEquals(calls(), 1);
});

Deno.test("fetchWithRetry retries a 402, 429 or 5xx until it succeeds", async () => {
  const { fetcher, calls } = responses(402, 503, 200);
  const waits: number[] = [];
  const res = await fetchWithRetry(fetcher, { delaysMs: [10, 20], sleep: (ms) => (waits.push(ms), Promise.resolve()) });
  assertEquals(res.status, 200);
  assertEquals(calls(), 3);
  assertEquals(waits, [10, 20]);
});

Deno.test("fetchWithRetry gives back the last failure once the retries run out", async () => {
  const { fetcher, calls } = responses(429);
  const res = await fetchWithRetry(fetcher, { delaysMs: [1, 1], sleep: () => Promise.resolve() });
  assertEquals(res.status, 429);
  assertEquals(calls(), 3);
});

Deno.test("fetchWithRetry does not retry a request the server rejected as bad", async () => {
  const { fetcher, calls } = responses(400, 200);
  const res = await fetchWithRetry(fetcher, { delaysMs: [1], sleep: () => Promise.resolve() });
  assertEquals(res.status, 400);
  assertEquals(calls(), 1);
  assertEquals(RETRY_STATUSES.has(400), false);
});

Deno.test("fetchWithRetry retries a network error, then rethrows it", async () => {
  let call = 0;
  const fetcher = () => (call++, Promise.reject(new TypeError("network down")));
  await assertRejects(() => fetchWithRetry(fetcher, { delaysMs: [1], sleep: () => Promise.resolve() }), TypeError);
  assertEquals(call, 2);
});

// IMP-10: every upstream attempt carries a deadline, and chat, moderation and image
// get one jittered retry on 429/5xx.

/** A fetcher that never answers until its signal aborts, like a hung upstream. */
function hangingFetcher() {
  let call = 0;
  const fetcher = (signal?: AbortSignal) => {
    call++;
    return new Promise<Response>((_, reject) => {
      signal?.addEventListener("abort", () => reject(signal.reason));
    });
  };
  return { fetcher, calls: () => call };
}

Deno.test("fetchWithRetry aborts a hung attempt at its deadline and reports an upstream timeout", async () => {
  const { fetcher, calls } = hangingFetcher();
  const error = await assertRejects(
    () => fetchWithRetry(fetcher, { delaysMs: [1], sleep: () => Promise.resolve(), timeoutMs: 20, label: "Image generation" }),
    PopError,
  );
  assertEquals(error.code, "upstream");
  assertEquals(error.message, "Image generation timed out");
  assertEquals(calls(), 1, "a timed-out attempt is not retried, so the deadline bounds the call");
});

Deno.test("fetchWithOneRetry retries a 429 or 5xx once after a jittered wait", async () => {
  for (const status of [429, 500, 503]) {
    const { fetcher, calls } = responses(status, 200);
    const waits: number[] = [];
    const res = await fetchWithOneRetry(fetcher, {
      timeoutMs: 1_000,
      label: "Model request",
      sleep: (ms) => (waits.push(ms), Promise.resolve()),
      random: () => 0.5,
    });
    assertEquals(res.status, 200);
    assertEquals(calls(), 2);
    assertEquals(waits, [jitteredDelayMs(0.5)]);
  }
});

Deno.test("fetchWithOneRetry gives up after one retry and returns the failure", async () => {
  const { fetcher, calls } = responses(503);
  const res = await fetchWithOneRetry(fetcher, { timeoutMs: 1_000, label: "x", sleep: () => Promise.resolve() });
  assertEquals(res.status, 503);
  assertEquals(calls(), 2);
});

Deno.test("fetchWithOneRetry does not retry a 402 or another 4xx", async () => {
  for (const status of [400, 401, 402]) {
    const { fetcher, calls } = responses(status, 200);
    const res = await fetchWithOneRetry(fetcher, { timeoutMs: 1_000, label: "x", sleep: () => Promise.resolve() });
    assertEquals(res.status, status);
    assertEquals(calls(), 1);
  }
});

Deno.test("fetchWithOneRetry passes each attempt an abort signal", async () => {
  const signals: (AbortSignal | undefined)[] = [];
  const fetcher = (signal?: AbortSignal) => (signals.push(signal), Promise.resolve(new Response("{}", { status: 200 })));
  await fetchWithOneRetry(fetcher, { timeoutMs: 1_000, label: "x" });
  assertEquals(signals.length, 1);
  assert(signals[0] instanceof AbortSignal);
});

Deno.test("jitteredDelayMs spreads the retry wait between 250 and 750 ms", () => {
  assertEquals(jitteredDelayMs(0), 250);
  assertEquals(jitteredDelayMs(0.5), 500);
  assert(jitteredDelayMs(0.999) < 750);
});
