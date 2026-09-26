import assert from "node:assert/strict";
import { test } from "node:test";

import { RevealState } from "../src/reveal.ts";

test("a generation nobody asked about is shown on its first frame", () => {
  const reveals = new RevealState();
  assert.deepEqual(reveals.firstFrame(1), { background: false });
});

test("a hidden generation's first frame reports background and stays hidden", () => {
  const reveals = new RevealState();
  reveals.request(2, false);
  assert.equal(reveals.isShown(2), false);
  assert.deepEqual(reveals.firstFrame(2), { background: true });
});

test("start can override what prepare recorded, either way", () => {
  const reveals = new RevealState();
  reveals.request(3, false);
  reveals.request(3, true);
  assert.deepEqual(reveals.firstFrame(3), { background: false });

  reveals.request(4, true);
  reveals.request(4, false);
  assert.deepEqual(reveals.firstFrame(4), { background: true });
});

test("reveal before the first frame: the first frame then shows the video", () => {
  const reveals = new RevealState();
  reveals.request(5, false);
  assert.deepEqual(reveals.reveal(5, 5), { revealed: true, hasFirstFrame: false });
  assert.deepEqual(reveals.firstFrame(5), { background: false });
});

test("reveal after the first frame reports it, so the caller shows the video now", () => {
  const reveals = new RevealState();
  reveals.request(6, false);
  assert.deepEqual(reveals.firstFrame(6), { background: true });
  assert.deepEqual(reveals.reveal(6, 6), { revealed: true, hasFirstFrame: true });
  assert.deepEqual(reveals.reveal(6, 6), { revealed: true, hasFirstFrame: true }); // idempotent
  assert.equal(reveals.isShown(6), true);
});

test("a revealed generation stays revealed even if start later asks to hide it", () => {
  const reveals = new RevealState();
  reveals.request(7, false);
  reveals.reveal(7, 7);
  reveals.request(7, false);
  assert.deepEqual(reveals.firstFrame(7), { background: false });
});

test("a stale reveal is refused and changes nothing", () => {
  const reveals = new RevealState();
  reveals.request(8, false);
  reveals.firstFrame(8);
  assert.deepEqual(reveals.reveal(8, 9), { revealed: false, hasFirstFrame: false });
  assert.equal(reveals.isShown(8), false);
  assert.deepEqual(reveals.reveal(3, 0), { revealed: false, hasFirstFrame: false }); // no flow yet
  assert.deepEqual(reveals.reveal(0, 0), { revealed: false, hasFirstFrame: false });
});

test("a newer generation replaces the older one's bookkeeping", () => {
  const reveals = new RevealState();
  reveals.request(9, false);
  reveals.firstFrame(9);
  reveals.request(10, false);
  assert.deepEqual(reveals.reveal(10, 10), { revealed: true, hasFirstFrame: false });
});

test("clear forgets shown and first-frame state", () => {
  const reveals = new RevealState();
  reveals.request(11, false);
  reveals.firstFrame(11);
  reveals.clear();
  assert.equal(reveals.isShown(11), true); // back to the default
  assert.deepEqual(reveals.reveal(11, 11), { revealed: true, hasFirstFrame: false });
});
