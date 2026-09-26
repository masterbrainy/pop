import { assertEquals } from "jsr:@std/assert@1";
import { checkInputSafety, kidRealHarmNote, type InputSafetyDeps } from "./input_safety.ts";
import { gentleParentNote } from "./safety.ts";

function fakeDeps(overrides: Partial<InputSafetyDeps> = {}): InputSafetyDeps {
  return {
    moderateText: async () => ({ flagged: false, categories: [] }),
    checkRealHarm: async () => ({ safe: true, reason: "" }),
    ...overrides,
  };
}

Deno.test("checkInputSafety treats empty input as trivially safe and skips both network calls", async () => {
  let moderateCalled = false;
  let rubricCalled = false;
  const deps = fakeDeps({
    moderateText: async () => {
      moderateCalled = true;
      return { flagged: false, categories: [] };
    },
    checkRealHarm: async () => {
      rubricCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("   ", "kid", "Maya", deps);
  assertEquals(verdict, { blocked: false, parentNote: null });
  assertEquals(moderateCalled, false);
  assertEquals(rubricCalled, false);
});

Deno.test("checkInputSafety passes safe text from either speaker", async () => {
  const deps = fakeDeps();
  const parentVerdict = await checkInputSafety("wake the dragon up", "parent", "Maya", deps);
  const kidVerdict = await checkInputSafety("add a puppy", "kid", "Maya", deps);
  assertEquals(parentVerdict.blocked, false);
  assertEquals(kidVerdict.blocked, false);
});

Deno.test("checkInputSafety blocks moderation-flagged input from a kid with the calm real-harm note, and skips the rubric call", async () => {
  let rubricCalled = false;
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkRealHarm: async () => {
      rubricCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("something unsafe", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, kidRealHarmNote("Maya"));
  assertEquals(rubricCalled, false);
});

Deno.test("checkInputSafety blocks moderation-flagged input from a parent with the generic gentle redirect note", async () => {
  const deps = fakeDeps({ moderateText: async () => ({ flagged: true, categories: [] }) });
  const verdict = await checkInputSafety("something unsafe", "parent", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, gentleParentNote());
});

Deno.test("checkInputSafety runs the real-harm rubric only for a kid speaker, and blocks with the kid note when it fails", async () => {
  const deps = fakeDeps({ checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }) });
  const verdict = await checkInputSafety("my uncle hurts me", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, kidRealHarmNote("Maya"));
});

Deno.test("checkInputSafety never runs the real-harm rubric for a parent speaker", async () => {
  let rubricCalled = false;
  const deps = fakeDeps({
    checkRealHarm: async () => {
      rubricCalled = true;
      return { safe: false, reason: "should never be called" };
    },
  });
  const verdict = await checkInputSafety("anything", "parent", "Maya", deps);
  assertEquals(verdict.blocked, false);
  assertEquals(rubricCalled, false);
});
