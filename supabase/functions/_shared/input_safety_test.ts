import { assertEquals } from "jsr:@std/assert@1";
import { checkInputSafety, kidRealHarmNote, type InputSafetyDeps } from "./input_safety.ts";
import { gentleParentNote } from "./safety.ts";

function fakeDeps(overrides: Partial<InputSafetyDeps> = {}): InputSafetyDeps {
  return {
    moderateText: async () => ({ flagged: false, categories: [] }),
    checkRealHarm: async () => ({ safe: true, reason: "" }),
    checkDirectionSafety: async () => ({ safe: true, reason: "" }),
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
  assertEquals(verdict, { blocked: false, parentNote: null, refusal: null });
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

Deno.test("checkInputSafety blocks moderation-flagged input from a kid with the calm real-harm note when the real-harm rubric agrees", async () => {
  // R-42: moderation alone never decides "real_harm" — the dedicated rubric does.
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }),
  });
  const verdict = await checkInputSafety("something unsafe", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, kidRealHarmNote("Maya"));
  assertEquals(verdict.refusal, "real_harm");
});

Deno.test("checkInputSafety blocks moderation-flagged playful pretend content from a kid as 'unsafe', not 'real_harm' (R-42)", async () => {
  // "The dragon fights the knight!" can trip content moderation's violence
  // category, but the real-harm rubric correctly reads it as pretend play —
  // it must still be a gentle, generic block, never the alarming real-harm
  // disclosure note.
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkRealHarm: async () => ({ safe: true, reason: "" }),
  });
  const verdict = await checkInputSafety("the dragon fights the knight", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, gentleParentNote());
  assertEquals(verdict.refusal, "unsafe");
});

Deno.test("checkInputSafety runs the real-harm rubric for a kid speaker even when moderation doesn't flag anything", async () => {
  let rubricCalled = false;
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: false, categories: [] }),
    checkRealHarm: async () => {
      rubricCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("add a puppy", "kid", "Maya", deps);
  assertEquals(verdict.blocked, false);
  assertEquals(rubricCalled, true);
});

Deno.test("checkInputSafety blocks moderation-flagged input from a parent when the direction-safety second opinion agrees it's unsafe", async () => {
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: [] }),
    checkDirectionSafety: async () => ({ safe: false, reason: "genuinely unsafe" }),
  });
  const verdict = await checkInputSafety("something unsafe", "parent", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, gentleParentNote());
  assertEquals(verdict.refusal, "unsafe");
});

Deno.test("checkInputSafety allows a parent's moderation-flagged-but-benign direction through, via the direction-safety second opinion (R-41 root cause)", async () => {
  // Regression: OpenAI's moderation model flagged the entirely benign
  // "Let's finish the story here with a proper ending." under its "violence"
  // category (observed live against the deployed function). The second
  // opinion catches this false positive and lets the direction through.
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkDirectionSafety: async () => ({ safe: true, reason: "" }),
  });
  const verdict = await checkInputSafety("Let's finish the story here with a proper ending.", "parent", "Maya", deps);
  assertEquals(verdict, { blocked: false, parentNote: null, refusal: null });
});

Deno.test("checkInputSafety never calls the direction-safety second opinion when moderation doesn't flag anything", async () => {
  let secondOpinionCalled = false;
  const deps = fakeDeps({
    checkDirectionSafety: async () => {
      secondOpinionCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("wake the dragon up", "parent", "Maya", deps);
  assertEquals(verdict.blocked, false);
  assertEquals(secondOpinionCalled, false);
});

Deno.test("checkInputSafety never calls the direction-safety second opinion for a kid speaker", async () => {
  let secondOpinionCalled = false;
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkRealHarm: async () => ({ safe: true, reason: "" }),
    checkDirectionSafety: async () => {
      secondOpinionCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("the dragon fights the knight", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(secondOpinionCalled, false);
});

Deno.test("checkInputSafety runs the real-harm rubric only for a kid speaker, and blocks with the kid note and refusal 'real_harm' when it fails", async () => {
  const deps = fakeDeps({ checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }) });
  const verdict = await checkInputSafety("my uncle hurts me", "kid", "Maya", deps);
  assertEquals(verdict.blocked, true);
  assertEquals(verdict.parentNote, kidRealHarmNote("Maya"));
  assertEquals(verdict.refusal, "real_harm");
});

Deno.test("checkInputSafety never runs the real-harm rubric for a parent's typed direction", async () => {
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

Deno.test("checkInputSafety runs the real-harm rubric on speech under the parent toggle, since a kid may be talking (R-44)", async () => {
  const deps = fakeDeps({ checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }) });
  const verdict = await checkInputSafety("my uncle hurts me", "parent", "Maya", deps, "speech");
  assertEquals(verdict, { blocked: true, parentNote: kidRealHarmNote("Maya"), refusal: "real_harm" });
});

Deno.test("checkInputSafety lets a parent's safe speech through after the real-harm check", async () => {
  let rubricCalled = false;
  const deps = fakeDeps({
    checkRealHarm: async () => {
      rubricCalled = true;
      return { safe: true, reason: "" };
    },
  });
  const verdict = await checkInputSafety("wake the dragon up", "parent", "Maya", deps, "speech");
  assertEquals(verdict.blocked, false);
  assertEquals(rubricCalled, true);
});

Deno.test("checkInputSafety still gives a parent's flagged speech the second opinion when it isn't real harm", async () => {
  const deps = fakeDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkDirectionSafety: async () => ({ safe: false, reason: "too scary" }),
  });
  const verdict = await checkInputSafety("something scary", "parent", "Maya", deps, "speech");
  assertEquals(verdict, { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" });
});

// --- IMP-25: a tapped choice ---

function countingDeps(flagged: boolean) {
  const calls = { moderate: 0, realHarm: 0, secondOpinion: 0 };
  const deps = fakeDeps({
    moderateText: async () => {
      calls.moderate += 1;
      return { flagged, categories: flagged ? ["violence"] : [] };
    },
    checkRealHarm: async () => {
      calls.realHarm += 1;
      return { safe: true, reason: "" };
    },
    checkDirectionSafety: async () => {
      calls.secondOpinion += 1;
      return { safe: true, reason: "" };
    },
  });
  return { deps, calls };
}

Deno.test("checkInputSafety moderates a choice only: no real-harm rubric and no second opinion", async () => {
  const { deps, calls } = countingDeps(false);
  const verdict = await checkInputSafety("The dragon looks under the bed.", "kid", "Maya", deps, "choice");
  assertEquals(verdict, { blocked: false, parentNote: null, refusal: null });
  assertEquals(calls, { moderate: 1, realHarm: 0, secondOpinion: 0 });
});

Deno.test("checkInputSafety blocks a moderation-flagged choice with the gentle note and refusal 'unsafe'", async () => {
  const { deps, calls } = countingDeps(true);
  const verdict = await checkInputSafety("something the app should never send", "kid", "Maya", deps, "choice");
  assertEquals(verdict, { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" });
  assertEquals(calls, { moderate: 1, realHarm: 0, secondOpinion: 0 });
});
