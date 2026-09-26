// IMP-10: the OpenAI chat and moderation clients and the Gemini image client each send a
// deadline signal with every request and retry a 503 once. `fetch` is stubbed, so
// no network call (and no paid API) is made.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { chatJSON } from "./openai_chat.ts";
import { moderateText } from "./openai_moderation.ts";
import { generateImage } from "./gemini_client.ts";
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

async function withRecordedFetch(replies: Response[], run: () => Promise<void>): Promise<{ url: string; init?: RequestInit }[]> {
  const original = globalThis.fetch;
  const calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return Promise.resolve(replies[Math.min(calls.length - 1, replies.length - 1)]);
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return calls;
}

const picture = () => json({ candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: "aW1n" } }] } }] });

Deno.test("chatJSON sends a picture alongside the text when given one", async () => {
  const calls = await withRecordedFetch([json({ choices: [{ message: { content: "{}" } }] })], async () => {
    await chatJSON("key", {
      model: "m", system: "s", user: "u", jsonSchema: { name: "n", strict: true, schema: {} },
      imageDataUrl: "data:image/png;base64,aW1n",
    });
  });
  const sent = JSON.parse(String(calls[0].init?.body));
  assertEquals(sent.messages[1].content, [
    { type: "text", text: "u" },
    { type: "image_url", image_url: { url: "data:image/png;base64,aW1n" } },
  ]);
});

Deno.test("generateImage asks Gemini for the page's 16:9 shape", async () => {
  let base64 = "";
  const calls = await withRecordedFetch([picture()], async () => {
    base64 = (await generateImage("key", { prompt: "a fox", aspectRatio: "16:9" })).base64;
  });
  assertEquals(base64, "aW1n");
  assert(calls[0].url.endsWith(":generateContent"));
  assertEquals(JSON.parse(String(calls[0].init?.body)).generationConfig.imageConfig.aspectRatio, "16:9");
});

Deno.test("generateImage retries a 402 burst once, with a deadline on each attempt", async () => {
  const signals = await withStubbedFetch([new Response("busy", { status: 402 }), picture()], async () => {
    await generateImage("key", { prompt: "a fox", aspectRatio: "16:9" });
  });
  assertEquals(signals.length, 2);
  assert(signals.every((signal) => signal instanceof AbortSignal));
});

Deno.test("generateImage gives up as upstream after one retry", async () => {
  const signals = await withStubbedFetch([busy(), busy(), picture()], async () => {
    const error = await assertRejects(() => generateImage("key", { prompt: "x", aspectRatio: "16:9" }), PopError);
    assertEquals(error.code, "upstream");
  });
  assertEquals(signals.length, 2);
});
