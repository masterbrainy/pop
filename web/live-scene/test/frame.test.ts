import assert from "node:assert/strict";
import { test } from "node:test";

import { frameSize, stripDataUrl } from "../src/frame.ts";

test("frameSize scales the long side down to the limit and keeps the aspect", () => {
  assert.deepEqual(frameSize(2560, 1440, 512), { width: 512, height: 288 });
  assert.deepEqual(frameSize(1440, 2560, 512), { width: 288, height: 512 });
});

test("frameSize never scales up and never returns zero", () => {
  assert.deepEqual(frameSize(320, 180, 512), { width: 320, height: 180 });
  assert.deepEqual(frameSize(4000, 1, 512), { width: 512, height: 1 });
  assert.equal(frameSize(0, 0, 512), null);
});

test("stripDataUrl returns the base64 payload and its type", () => {
  assert.deepEqual(stripDataUrl("data:image/jpeg;base64,QUJD"), { mimeType: "image/jpeg", base64: "QUJD" });
  assert.equal(stripDataUrl("data:,"), null);
  assert.equal(stripDataUrl("nonsense"), null);
});
