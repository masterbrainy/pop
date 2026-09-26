import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { fetchWithRetry, RETRY_STATUSES } from "./retry.ts";

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
