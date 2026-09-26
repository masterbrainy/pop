import assert from "node:assert/strict";
import { test } from "node:test";

import { checkClipGeneration, chunkCount, pickMimeType, toBase64 } from "../src/clip.ts";
import { SupersededError, isSuperseded } from "../src/gate.ts";

test("pickMimeType prefers H.264 MP4, then plain MP4, then WebM", () => {
  assert.equal(pickMimeType(() => true), "video/mp4;codecs=avc1");
  assert.equal(pickMimeType((t) => t === "video/mp4"), "video/mp4");
  assert.equal(pickMimeType((t) => t.startsWith("video/webm")), "video/webm;codecs=vp8");
  assert.equal(pickMimeType(() => false), null);
});

test("toBase64 matches Node's encoder, across the 32 KB step", () => {
  const bytes = new Uint8Array(70_000).map((_, i) => (i * 31) % 256);
  assert.equal(toBase64(bytes), Buffer.from(bytes).toString("base64"));
  assert.equal(toBase64(new Uint8Array()), "");
});

test("chunkCount splits into 256 KB chunks and never returns zero", () => {
  assert.equal(chunkCount(0), 1);
  assert.equal(chunkCount(256 * 1024), 1);
  assert.equal(chunkCount(256 * 1024 + 1), 2);
});

test("checkClipGeneration refuses a clip for a page flow that is no longer the newest", () => {
  const newest = 4;
  const isCurrent = (generation: number) => generation === newest;
  assert.doesNotThrow(() => checkClipGeneration(undefined, isCurrent)); // no generation: as before
  assert.doesNotThrow(() => checkClipGeneration(4, isCurrent));
  assert.throws(
    () => checkClipGeneration(3, isCurrent),
    (error: unknown) => error instanceof SupersededError && error.generation === 3 && isSuperseded(error),
  );
});
