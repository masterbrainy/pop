import { assertEquals } from "jsr:@std/assert@1";
import { planNewPath, runPageTurn, runPathTurn, type RunPageTurnDeps, type RunPathTurnDeps } from "./story_path.ts";
import type { StoryBible } from "./schemas.ts";
import type { StoryPageModelOutput, StoryPathModelOutput } from "./story_path_schema.ts";

function pathOutput(overrides: Partial<StoryPathModelOutput> = {}): StoryPathModelOutput {
  return {
    path: ["Maya finds a red kite in the meadow.", "Maya falls asleep holding the kite. The end."],
    isEnding: false,
    pageText: "Maya finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    readingQuestion: "What colour is the kite?",
    bibleTitle: null,
    bibleSetting: "A sunny meadow",
    bibleCharacters: [{ id: "maya", name: "Maya", description: "a curious kid" }],
    bibleDirections: [],
    parentNote: null,
    ...overrides,
  };
}

function pageOutput(overrides: Partial<StoryPageModelOutput> = {}): StoryPageModelOutput {
  return {
    pageText: "Maya finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    readingQuestion: "What colour is the kite?",
    parentNote: null,
    ...overrides,
  };
}

const emptyBible: StoryBible = { title: null, setting: "", characters: [], directions: [], path: [] };

function safeInputSafety() {
  return {
    moderateText: async () => ({ flagged: false, categories: [] }),
    checkRealHarm: async () => ({ safe: true, reason: "" }),
  };
}

function pathDepsFor(outputs: StoryPathModelOutput[], safe: boolean[]): RunPathTurnDeps {
  let modelCall = 0;
  let safetyCall = 0;
  return {
    callModel: async () => ({ output: outputs[modelCall++], modelMs: 10 }),
    safety: {
      moderateText: async () => ({ flagged: false, categories: [] }),
      checkRubric: async () => ({ safe: safe[safetyCall++], reason: safe[safetyCall - 1] ? "" : "too scary" }),
    },
    inputSafety: safeInputSafety(),
  };
}

function pageDepsFor(outputs: StoryPageModelOutput[], safe: boolean[]): RunPageTurnDeps {
  let modelCall = 0;
  let safetyCall = 0;
  return {
    callModel: async () => ({ output: outputs[modelCall++], modelMs: 10 }),
    safety: {
      moderateText: async () => ({ flagged: false, categories: [] }),
      checkRubric: async () => ({ safe: safe[safetyCall++], reason: safe[safetyCall - 1] ? "" : "too scary" }),
    },
  };
}

// --- planNewPath (pure) ---

Deno.test("planNewPath keeps every beat before index unchanged and appends the newly planned beats", () => {
  const existing = ["Beat 0", "Beat 1 (about to change)", "Beat 2 (about to change)"];
  const { path } = planNewPath(existing, 1, ["Beat 1 replanned", "Beat 2 replanned", "Beat 3 the end"]);
  assertEquals(path, ["Beat 0", "Beat 1 replanned", "Beat 2 replanned", "Beat 3 the end"]);
});

Deno.test("planNewPath ignores anything a model attempt echoes back for beats before index", () => {
  // Even if newBeatsFromIndex somehow included an "echo" of an earlier beat, only
  // existing.slice(0, index) is ever used for the kept portion — beats before
  // index always come from the caller's existing path, never from the model.
  const existing = ["Beat 0 (locked)"];
  const { path } = planNewPath(existing, 1, ["Beat 1"]);
  assertEquals(path[0], "Beat 0 (locked)");
});

Deno.test("planNewPath marks isEnding true only when index is the last beat of the full path", () => {
  const existing: string[] = [];
  assertEquals(planNewPath(existing, 0, ["only beat, the end"]).isEnding, true);
  assertEquals(planNewPath(existing, 0, ["first beat", "second beat"]).isEnding, false);
  assertEquals(planNewPath(["kept"], 1, ["last beat, the end"]).isEnding, true);
});

// --- runPathTurn ---

Deno.test("runPathTurn plans the path and writes page index on the first safe attempt", async () => {
  const deps = pathDepsFor([pathOutput()], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.index, 0);
  assertEquals(result.bible.path, ["Maya finds a red kite in the meadow.", "Maya falls asleep holding the kite. The end."]);
  assertEquals(result.parentNote, null);
});

Deno.test("runPathTurn keeps beats before index when re-planning from a direction", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Maya finds a red kite in the meadow."] };
  const deps = pathDepsFor(
    [pathOutput({ path: ["Maya wakes the sleepy dragon.", "The dragon and Maya nap together. The end."] })],
    [true],
  );
  const result = await runPathTurn("early_reader", 1, bible, "Maya", { text: "wake the dragon up", speaker: "parent" }, deps);
  assertEquals(result.bible.path, [
    "Maya finds a red kite in the meadow.",
    "Maya wakes the sleepy dragon.",
    "The dragon and Maya nap together. The end.",
  ]);
});

Deno.test("runPathTurn reports isEnding for the path's last beat", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Maya falls asleep. The end."] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPathTurn reports isEnding false for a beat that isn't last", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Beat one", "Beat two, the end"] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn rewrites once when the first attempt fails the gate, then returns the rewrite", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Something scary happens." }), pathOutput({ pageText: "Something gentle happens." })],
    [false, true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.page.text, "Something gentle happens.");
});

Deno.test("runPathTurn falls back to none with a gentle parentNote after two failed attempts", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Bad one" }), pathOutput({ pageText: "Still bad" })],
    [false, false],
  );
  const result = await runPathTurn("listener", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.action, "none");
  assertEquals(result.bible, emptyBible);
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPathTurn blocks a flagged direction from a kid before any model call, returning none with refusal 'real_harm'", async () => {
  let modelCalled = false;
  const deps: RunPathTurnDeps = {
    callModel: async () => {
      modelCalled = true;
      return { output: pathOutput(), modelMs: 10 };
    },
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
    inputSafety: { moderateText: async () => ({ flagged: true, categories: ["violence"] }), checkRealHarm: async () => ({ safe: true, reason: "" }) },
  };
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Maya", { text: "unsafe direction", speaker: "kid" }, deps);
  assertEquals(result.action, "none");
  assertEquals(result.bible, bible);
  assertEquals(modelCalled, false);
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "real_harm");
});

Deno.test("runPathTurn blocks a flagged direction from a parent, returning none with refusal 'unsafe'", async () => {
  const deps: RunPathTurnDeps = {
    callModel: async () => ({ output: pathOutput(), modelMs: 10 }),
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
    inputSafety: { moderateText: async () => ({ flagged: true, categories: ["violence"] }), checkRealHarm: async () => ({ safe: true, reason: "" }) },
  };
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Maya", { text: "unsafe direction", speaker: "parent" }, deps);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPathTurn returns refusal null on a successful page", async () => {
  const deps = pathDepsFor([pathOutput()], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", null, deps);
  assertEquals(result.refusal, null);
});

// --- runPageTurn ---

Deno.test("runPageTurn writes page index from the existing beat, with no re-planning", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Maya finds a red kite in the meadow.", "Maya falls asleep. The end."] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 0, bible, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.index, 0);
  assertEquals(result.page.isEnding, false);
  assertEquals(result.bible, bible);
  assertEquals(result.refusal, null);
});

Deno.test("runPageTurn reports isEnding true for the path's last index", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1, the end"] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 1, bible, deps);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPageTurn past the path's end returns none with no model call", async () => {
  let modelCalled = false;
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps: RunPageTurnDeps = {
    callModel: async () => {
      modelCalled = true;
      return { output: pageOutput(), modelMs: 10 };
    },
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
  };
  const result = await runPageTurn("early_reader", 1, bible, deps);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote, "The story has reached its ending.");
  assertEquals(modelCalled, false);
  assertEquals(result.bible, bible);
  assertEquals(result.refusal, null);
});

Deno.test("runPageTurn rewrites once when the first attempt fails the gate", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor(
    [pageOutput({ pageText: "Something scary." }), pageOutput({ pageText: "Something gentle." })],
    [false, true],
  );
  const result = await runPageTurn("early_reader", 0, bible, deps);
  assertEquals(result.page.text, "Something gentle.");
});

Deno.test("runPageTurn falls back to none after two failed attempts", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor([pageOutput({ pageText: "Bad" }), pageOutput({ pageText: "Still bad" })], [false, false]);
  const result = await runPageTurn("listener", 0, bible, deps);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPageTurn drops a page that retells an earlier shown page", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1"] };
  const earlier = ["Maya the little blue dragon finds a shiny red kite in the meadow."];
  const deps = pageDepsFor(
    [pageOutput({ pageText: "Maya the little blue dragon finds a shiny red kite in the meadow. She smiles and lifts it high." })],
    [true],
  );
  const result = await runPageTurn("reader", 1, bible, deps, earlier);
  assertEquals(result.page.text, "She smiles and lifts it high.");
});

Deno.test("runPageTurn trims an overlong page to the reading level's word limit instead of refusing it", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const tooLong = Array(20).fill("word").join(" "); // 20 words > listener's 15-word cap
  const deps = pageDepsFor([pageOutput({ pageText: tooLong })], [true]);
  const result = await runPageTurn("listener", 0, bible, deps);
  assertEquals(result.page.text.split(" ").length, 15);
});
