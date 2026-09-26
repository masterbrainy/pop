import assert from "node:assert/strict";
import { test } from "node:test";

import { DELIVERY_COMMANDS, chunkIndexOf, describeMessage, unwrapOrbisMessage } from "../src/orbis.ts";
import { MessageWaiters } from "../src/waiters.ts";

test("unwrap flattens a { type, data } envelope", () => {
  const message = unwrapOrbisMessage({ type: "state", data: { has_image: true, current_chunk: 4 } });
  assert.deepEqual(message, { has_image: true, current_chunk: 4, type: "state" });
});

test("unwrap passes a bare message through", () => {
  assert.deepEqual(unwrapOrbisMessage({ type: "conditions_ready" }), { type: "conditions_ready" });
});

test("unwrap turns null and primitives into an empty message", () => {
  assert.deepEqual(unwrapOrbisMessage(null), {});
  assert.deepEqual(unwrapOrbisMessage("nope"), {});
});

test("unwrap ignores an array data field", () => {
  assert.deepEqual(unwrapOrbisMessage({ type: "x", data: [1] }), { type: "x", data: [1] });
});

test("chunk index prefers the wire name, then the documented names", () => {
  assert.equal(chunkIndexOf({ chunk_index: 7, session_chunk: 1 }), 7);
  assert.equal(chunkIndexOf({ session_chunk: 3 }), 3);
  assert.equal(chunkIndexOf({ current_chunk: 2 }), 2);
  assert.equal(chunkIndexOf({ type: "state" }), null);
});

test("describe bounds long messages and survives cycles", () => {
  assert.equal(describeMessage({ a: 1 }), '{"a":1}');
  assert.ok(describeMessage({ text: "x".repeat(5_000) }).endsWith("…"));
  const cyclic: Record<string, unknown> = {};
  cyclic.self = cyclic;
  assert.equal(describeMessage(cyclic), "[object Object]");
});

test("waiters resolve on the first matching message only", async () => {
  const waiters = new MessageWaiters();
  const ready = waiters.waitFor((m) => m.type === "conditions_ready", 1_000, "conditions_ready");
  waiters.dispatch({ type: "state" });
  assert.equal(waiters.count, 1);
  waiters.dispatch({ type: "conditions_ready" });
  assert.deepEqual(await ready, { type: "conditions_ready" });
  assert.equal(waiters.count, 0);
});

test("waiters time out with the label in the error", async () => {
  const waiters = new MessageWaiters();
  await assert.rejects(waiters.waitFor(() => false, 10, "state.has_image"), /state\.has_image did not arrive/);
  assert.equal(waiters.count, 0);
});

test("rejectAll fails every pending waiter", async () => {
  const waiters = new MessageWaiters();
  const first = waiters.waitFor(() => false, 1_000, "a");
  const second = waiters.waitFor(() => false, 1_000, "b");
  waiters.rejectAll(new Error("disconnected"));
  await assert.rejects(first, /disconnected/);
  await assert.rejects(second, /disconnected/);
  assert.equal(waiters.count, 0);
});

test("after connect Pop! asks for 1080p delivery and no audio", () => {
  assert.deepEqual(DELIVERY_COMMANDS, [
    { name: "set_resolution", data: { resolution: "1080p" } },
    { name: "set_audio_enabled", data: { audio_enabled: false } },
  ]);
});
