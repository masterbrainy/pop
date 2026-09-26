import assert from "node:assert/strict";
import { test } from "node:test";

import {
  FirstFrameWatch,
  GenerationGate,
  SupersededError,
  conditionsReadyTimeoutMs,
  isSuperseded,
} from "../src/gate.ts";

function deferred(): { promise: Promise<void>; resolve: () => void } {
  let resolve = () => {};
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

const tick = () => new Promise<void>((done) => setTimeout(done, 0));

test("a claimed generation runs its task and resolves with its value", async () => {
  const gate = new GenerationGate(() => {});
  assert.equal(await gate.claim(1, async () => "page one"), "page one");
  assert.equal(gate.latest, 1);
});

test("a newer claim supersedes the older flow: its guard throws and the hook fires once", async () => {
  const superseded: number[] = [];
  const gate = new GenerationGate((error) => superseded.push(error.generation));
  const step = deferred();
  const older = gate.claim(1, async (guard) => {
    await step.promise;
    guard();
    return "older finished";
  });
  const newer = gate.claim(2, async () => "newer finished");
  step.resolve();

  await assert.rejects(older, (error: unknown) => isSuperseded(error));
  assert.equal(await newer, "newer finished");
  assert.deepEqual(superseded, [1]);
});

test("the newer flow waits until the older one settles before it touches the session", async () => {
  const gate = new GenerationGate(() => {});
  const order: string[] = [];
  const step = deferred();
  const older = gate.claim(1, async () => {
    order.push("older begins");
    await step.promise;
    order.push("older ends");
  });
  await tick();
  const newer = gate.claim(2, async () => {
    order.push("newer begins");
  });
  await tick();
  assert.deepEqual(order, ["older begins"]);
  step.resolve();
  await older;
  await newer;
  assert.deepEqual(order, ["older begins", "older ends", "newer begins"]);
});

test("an older flow that has not begun yet is skipped entirely", async () => {
  const gate = new GenerationGate(() => {});
  let olderRan = false;
  const older = gate.claim(1, async () => {
    olderRan = true;
  });
  const newer = gate.claim(2, async () => "newer");
  await assert.rejects(older, SupersededError);
  assert.equal(await newer, "newer");
  assert.equal(olderRan, false);
});

test("an older or repeated generation is rejected at once without running", async () => {
  const gate = new GenerationGate(() => {});
  await gate.claim(5, async () => undefined);
  let ran = false;
  await assert.rejects(
    gate.claim(4, async () => {
      ran = true;
    }),
    SupersededError,
  );
  await assert.rejects(gate.claim(5, async () => undefined), SupersededError);
  assert.equal(ran, false);
});

test("follow continues only the newest generation", async () => {
  const gate = new GenerationGate(() => {});
  await gate.claim(1, async () => undefined);
  assert.equal(await gate.follow(1, async () => "started"), "started");
  await gate.claim(2, async () => undefined);
  await assert.rejects(gate.follow(1, async () => "stale start"), SupersededError);
});

test("a newer claim during a follow supersedes it too", async () => {
  const gate = new GenerationGate(() => {});
  await gate.claim(1, async () => undefined);
  const step = deferred();
  const start = gate.follow(1, async (guard) => {
    await step.promise;
    guard();
  });
  const next = gate.claim(2, async () => "next page");
  step.resolve();
  await assert.rejects(start, SupersededError);
  assert.equal(await next, "next page");
});

test("a failed flow does not block the next one", async () => {
  const gate = new GenerationGate(() => {});
  await assert.rejects(
    gate.claim(1, async () => {
      throw new Error("set_image: rejected");
    }),
    /rejected/,
  );
  assert.equal(await gate.claim(2, async () => "ok"), "ok");
});

test("next() is one past the newest generation, for callers that pass none", async () => {
  const gate = new GenerationGate(() => {});
  assert.equal(gate.next(), 1);
  await gate.claim(7, async () => undefined);
  assert.equal(gate.next(), 8);
});

test("superseded errors are recognised by name and by message", () => {
  assert.equal(isSuperseded(new SupersededError(3)), true);
  assert.equal(isSuperseded(new Error("superseded: page flow 3 replaced by a newer one")), true);
  assert.equal(isSuperseded(new Error("conditions_ready did not arrive within 20 s")), false);
  assert.equal(isSuperseded("superseded"), false);
});

test("the first page after connect may take minutes; later pages get 20 s", () => {
  assert.equal(conditionsReadyTimeoutMs({ firstPageOnSession: true }), 300_000);
  assert.equal(conditionsReadyTimeoutMs({ firstPageOnSession: false }), 20_000);
});

test("a first frame counts only after generation_started for the armed generation", () => {
  const watch = new FirstFrameWatch();
  assert.equal(watch.isWatching, false);
  assert.equal(watch.onFrame(), null);

  watch.arm(3);
  assert.equal(watch.isWatching, true);
  assert.equal(watch.onFrame(), null); // a stale frame before the run began
  assert.equal(watch.isWatching, true);

  watch.generationStarted();
  assert.equal(watch.onFrame(), 3);
  assert.equal(watch.isWatching, false);
  assert.equal(watch.onFrame(), null); // reported once
});

test("re-arming or cancelling drops the older generation's first frame", () => {
  const watch = new FirstFrameWatch();
  watch.arm(3);
  watch.generationStarted();
  watch.arm(4);
  assert.equal(watch.onFrame(), null); // 4 has not started yet
  watch.generationStarted();
  assert.equal(watch.onFrame(), 4);

  watch.arm(5);
  watch.cancel();
  watch.generationStarted();
  assert.equal(watch.onFrame(), null);
  assert.equal(watch.isWatching, false);
});
