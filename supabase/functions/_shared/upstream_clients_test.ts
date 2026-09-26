// IMP-10: the OpenAI chat, OpenAI moderation and Gemini text clients each send a
// deadline signal with every request and retry a 503 once. `fetch` is stubbed, so
// no network call (and no paid API) is made.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { chatJSON } from "./openai_chat.ts";
import { moderateText } from "./openai_moderation.ts";
import { generateJSON } from "./gemini_client.ts";
import { PopError } from "./errors.ts";

async function withStubbedFetch(replies: Response[], run: () => Promise<void>): Promise<(AbortSignal | undefined)[]> {
  const original = globalThis.fetch;
  const signals: (AbortSignal | undefined)[] = [];
  let call = 0;
  globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
    signals.push(init?.signal ?? undefined);
    return Promise.resolve(replies[Math.min(call++, replies.length - 1)]);
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return signals;
}

const busy = () => new Response("busy", { status: 503 });
const json = (value: unknown) => new Response(JSON.stringify(value), { status: 200 });

Deno.test("chatJSON retries a 503 once and sends a deadline with each attempt", async () => {
  let content = "";
  const signals = await withStubbedFetch([busy(), json({ choices: [{ message: { content: "{}" } }] })], async () => {
    content = await chatJSON("key", { model: "m", system: "s", user: "u", jsonSchema: { name: "n", strict: true, schema: {} } });
  });
  assertEquals(content, "{}");
  assertEquals(signals.length, 2);
  assert(signals.every((signal) => signal instanceof AbortSignal));
});

Deno.test("moderateText retries a 503 once, then reports upstream if it fails again", async () => {
  const signals = await withStubbedFetch([busy(), busy(), json({})], async () => {
    const error = await assertRejects(() => moderateText("key", "hello"), PopError);
    assertEquals(error.code, "upstream");
  });
  assertEquals(signals.length, 2);
  assert(signals.every((signal) => signal instanceof AbortSignal));
});

Deno.test("generateJSON retries a 503 once and sends a deadline with each attempt", async () => {
  let text = "";
  const signals = await withStubbedFetch([busy(), json({ candidates: [{ content: { parts: [{ text: "{\"a\":1}" }] } }] })], async () => {
    text = await generateJSON("key", { instruction: "i", responseSchema: {} });
  });
  assertEquals(text, "{\"a\":1}");
  assertEquals(signals.length, 2);
  assert(signals.every((signal) => signal instanceof AbortSignal));
});
