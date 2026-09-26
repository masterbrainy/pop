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
    checkDirectionSafety: async () => ({ safe: true, reason: "" }),
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

// --- planNewPath (R-42: path-length and beat-length clamp) ---

Deno.test("planNewPath clamps the combined path to at most 12 beats", () => {
  const kept = ["Beat 0", "Beat 1", "Beat 2"];
  const overlong = Array.from({ length: 20 }, (_, i) => `New beat ${i}`);
  const { path, isEnding } = planNewPath(kept, 3, overlong);
  assertEquals(path.length, 12);
  assertEquals(path.slice(0, 3), kept);
  assertEquals(path[11], "New beat 8");
  // index 3 is not the last beat (path[11] is), so this call's own page isn't the ending.
  assertEquals(isEnding, false);
});

Deno.test("planNewPath always keeps room for index's own beat even if already at the cap", () => {
  const kept = Array.from({ length: 12 }, (_, i) => `Beat ${i}`);
  const { path, isEnding } = planNewPath(kept, 12, ["One more beat, the end"]);
  assertEquals(path.length, 13);
  assertEquals(isEnding, true);
});

Deno.test("planNewPath trims an overlong beat to whole sentences within 300 characters", () => {
  const longSentence = "A ".repeat(200) + "fox ran.";
  const { path } = planNewPath([], 0, [longSentence]);
  assertEquals(path[0].length <= 300, true);
});

Deno.test("planNewPath trims a single sentence with no break to a hard 300-character cut", () => {
  const oneHugeSentence = "word ".repeat(100).trim(); // no sentence punctuation at all
  const { path } = planNewPath([], 0, [oneHugeSentence]);
  assertEquals(path[0].length <= 300, true);
  assertEquals(path[0].endsWith("."), true);
});

Deno.test("planNewPath with forceEnd keeps only the first newly planned beat, ending at index", () => {
  const { path, isEnding } = planNewPath(["Beat 0"], 1, ["Beat 1", "Beat 2", "Beat 3, the end"], true);
  assertEquals(path, ["Beat 0", "Beat 1"]);
  assertEquals(isEnding, true);
});

// --- runPathTurn ---

Deno.test("runPathTurn plans the path and writes page index on the first safe attempt", async () => {
  const deps = pathDepsFor([pathOutput()], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
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
  const result = await runPathTurn("early_reader", 1, bible, "Maya", "en", { text: "wake the dragon up", speaker: "parent" }, deps);
  assertEquals(result.bible.path, [
    "Maya finds a red kite in the meadow.",
    "Maya wakes the sleepy dragon.",
    "The dragon and Maya nap together. The end.",
  ]);
});

Deno.test("runPathTurn reports isEnding for the path's last beat", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Maya falls asleep. The end."] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPathTurn reports isEnding false for a beat that isn't last", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Beat one", "Beat two, the end"] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn rewrites once when the first attempt fails the gate, then returns the rewrite", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Something scary happens." }), pathOutput({ pageText: "Something gentle happens." })],
    [false, true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.page.text, "Something gentle happens.");
});

Deno.test("runPathTurn falls back to none with a gentle parentNote after two failed attempts", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Bad one" }), pathOutput({ pageText: "Still bad" })],
    [false, false],
  );
  const result = await runPathTurn("listener", 0, emptyBible, "Maya", "en", null, deps);
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
    // R-42: the real-harm rubric (not moderation alone) decides refusal "real_harm" vs "unsafe" for a kid speaker.
    inputSafety: {
      moderateText: async () => ({ flagged: true, categories: ["violence"] }),
      checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }),
      checkDirectionSafety: async () => ({ safe: true, reason: "" }),
    },
  };
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Maya", "en", { text: "unsafe direction", speaker: "kid" }, deps);
  assertEquals(result.action, "none");
  assertEquals(result.bible, bible);
  assertEquals(modelCalled, false);
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "real_harm");
});

Deno.test("runPathTurn blocks a flagged direction from a parent when the direction-safety second opinion also says unsafe, returning none with refusal 'unsafe'", async () => {
  const deps: RunPathTurnDeps = {
    callModel: async () => ({ output: pathOutput(), modelMs: 10 }),
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
    inputSafety: {
      moderateText: async () => ({ flagged: true, categories: ["violence"] }),
      checkRealHarm: async () => ({ safe: true, reason: "" }),
      checkDirectionSafety: async () => ({ safe: false, reason: "genuinely unsafe" }),
    },
  };
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Maya", "en", { text: "unsafe direction", speaker: "parent" }, deps);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPathTurn returns refusal null on a successful page", async () => {
  const deps = pathDepsFor([pathOutput()], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.refusal, null);
});

Deno.test("runPathTurn fails the output gate on a foreign-script leak in an 'en' story, then accepts a clean rewrite", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({ pageText: "A friendly fox is рядом in the meadow." }),
      pathOutput({ pageText: "A friendly fox is nearby in the meadow." }),
    ],
    [true, true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "A friendly fox is nearby in the meadow.");
});

// --- runPathTurn (R-42) ---

Deno.test("runPathTurn allows the kid's own non-Latin name in an 'en' story", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "李明 finds a red kite in the meadow.", path: ["李明 finds a red kite in the meadow."] })],
    [true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "李明", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "李明 finds a red kite in the meadow.");
});

Deno.test("runPathTurn allows a bible character's non-Latin name in an 'en' story", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({
        pageText: "Maya waved to her friend Дима by the lake.",
        bibleCharacters: [
          { id: "maya", name: "Maya", description: "a curious kid" },
          { id: "dima", name: "Дима", description: "Maya's friend" },
        ],
      }),
    ],
    [true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "Maya waved to her friend Дима by the lake.");
});

Deno.test("runPathTurn still catches a real foreign-script leak alongside an allowed name", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({ pageText: "李明 is рядом in the meadow." }),
      pathOutput({ pageText: "李明 is nearby in the meadow." }),
    ],
    [true, true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "李明", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "李明 is nearby in the meadow.");
});

Deno.test("runPathTurn gates a flagged bibleTitle even when the page text itself is safe", async () => {
  const deps: RunPathTurnDeps = {
    callModel: async () => ({ output: pathOutput({ bibleTitle: "flagged title" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged title", categories: text === "flagged title" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
    inputSafety: safeInputSafety(),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "none");
});

Deno.test("runPathTurn gates a flagged successful parentNote even when the page text itself is safe", async () => {
  const deps: RunPathTurnDeps = {
    callModel: async () => ({ output: pathOutput({ parentNote: "flagged note" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged note", categories: text === "flagged note" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
    inputSafety: safeInputSafety(),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "none");
});

Deno.test("runPathTurn forces the path to end at index when the direction explicitly asks to end now", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pathDepsFor(
    [pathOutput({ path: ["Beat 1", "Beat 2", "Beat 3, the model kept going"], isEnding: false })],
    [true],
  );
  const result = await runPathTurn(
    "early_reader",
    1,
    bible,
    "Maya",
    "en",
    { text: "Let's finish the story here with a proper ending.", speaker: "parent" },
    deps,
  );
  assertEquals(result.bible.path, ["Beat 0", "Beat 1"]);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPathTurn does not force an early ending for an ordinary direction", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pathDepsFor(
    [pathOutput({ path: ["Beat 1", "Beat 2, the end"], isEnding: false })],
    [true],
  );
  const result = await runPathTurn(
    "early_reader",
    1,
    bible,
    "Maya",
    "en",
    { text: "wake the dragon up", speaker: "parent" },
    deps,
  );
  assertEquals(result.bible.path, ["Beat 0", "Beat 1", "Beat 2, the end"]);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn regression (ending-reader false block, R-41 root cause): an end-request direction that moderation misflags still reaches the model and forces the ending", async () => {
  // Reproduces the actual observed bug: OpenAI's moderation model flagged
  // "Let's finish the story here with a proper ending." under its "violence"
  // category even though the text is entirely benign. The direction-safety
  // second opinion must override that false positive so the turn isn't
  // blocked before ever reaching the model.
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  let modelCalled = false;
  const deps: RunPathTurnDeps = {
    callModel: async () => {
      modelCalled = true;
      return { output: pathOutput({ path: ["Beat 1, and they settle down together"], isEnding: false }), modelMs: 10 };
    },
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
    inputSafety: {
      moderateText: async () => ({ flagged: true, categories: ["violence"] }),
      checkRealHarm: async () => ({ safe: true, reason: "" }),
      checkDirectionSafety: async () => ({ safe: true, reason: "" }),
    },
  };
  const result = await runPathTurn(
    "reader",
    1,
    bible,
    "Elena",
    "en",
    { text: "Let's finish the story here with a proper ending.", speaker: "parent" },
    deps,
  );
  assertEquals(modelCalled, true);
  assertEquals(result.action, "page");
  assertEquals(result.page.isEnding, true);
});

// --- runPageTurn ---

Deno.test("runPageTurn writes page index from the existing beat, with no re-planning", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Maya finds a red kite in the meadow.", "Maya falls asleep. The end."] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.index, 0);
  assertEquals(result.page.isEnding, false);
  assertEquals(result.bible, bible);
  assertEquals(result.refusal, null);
});

Deno.test("runPageTurn reports isEnding true for the path's last index", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1, the end"] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 1, bible, "Maya", "en", deps);
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
  const result = await runPageTurn("early_reader", 1, bible, "Maya", "en", deps);
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
  const result = await runPageTurn("early_reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.page.text, "Something gentle.");
});

Deno.test("runPageTurn falls back to none after two failed attempts", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor([pageOutput({ pageText: "Bad" }), pageOutput({ pageText: "Still bad" })], [false, false]);
  const result = await runPageTurn("listener", 0, bible, "Maya", "en", deps);
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
  const result = await runPageTurn("reader", 1, bible, "Maya", "en", deps, earlier);
  assertEquals(result.page.text, "She smiles and lifts it high.");
});

Deno.test("runPageTurn trims an overlong page to the reading level's word limit instead of refusing it", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const tooLong = Array(20).fill("word").join(" "); // 20 words > listener's 15-word cap
  const deps = pageDepsFor([pageOutput({ pageText: tooLong })], [true]);
  const result = await runPageTurn("listener", 0, bible, "Maya", "en", deps);
  assertEquals(result.page.text.split(" ").length, 15);
});

Deno.test("runPageTurn fails the output gate on a foreign-script leak in an 'en' story, then accepts a clean rewrite", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor(
    [
      pageOutput({ pageText: "A friendly fox is рядом, and both look surprised." }),
      pageOutput({ pageText: "A friendly fox is nearby, and both look surprised." }),
    ],
    [true, true], // the rubric itself passes both times; the language check is what fails the first
  );
  const result = await runPageTurn("reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "A friendly fox is nearby, and both look surprised.");
});

Deno.test("runPageTurn falls back to none with refusal 'unsafe' when the rewrite still leaks a foreign script", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor(
    [
      pageOutput({ pageText: "A friendly fox is рядом." }),
      pageOutput({ pageText: "A friendly fox is снова рядом." }),
    ],
    [true, true],
  );
  const result = await runPageTurn("reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "none");
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPageTurn never checks language for a non-'en' brief", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor([pageOutput({ pageText: "Un renard sympathique est рядом." })], [true]);
  const result = await runPageTurn("reader", 0, bible, "Maya", "fr", deps);
  assertEquals(result.action, "page");
});

// --- runPageTurn (R-42) ---

Deno.test("runPageTurn allows the kid's own non-Latin name in an 'en' story", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["李明 finds a red kite in the meadow."] };
  const deps = pageDepsFor([pageOutput({ pageText: "李明 finds a red kite in the meadow." })], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "李明", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "李明 finds a red kite in the meadow.");
});

Deno.test("runPageTurn allows a bible character's non-Latin name in an 'en' story", async () => {
  const bible: StoryBible = {
    ...emptyBible,
    characters: [{ id: "dima", name: "Дима", description: "Maya's friend", referencePath: null }],
    path: ["Maya waved to her friend Дима by the lake."],
  };
  const deps = pageDepsFor([pageOutput({ pageText: "Maya waved to her friend Дима by the lake." })], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "Maya waved to her friend Дима by the lake.");
});

Deno.test("runPageTurn gates a flagged successful parentNote even when the page text itself is safe", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps: RunPageTurnDeps = {
    callModel: async () => ({ output: pageOutput({ parentNote: "flagged note" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged note", categories: text === "flagged note" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
  };
  const result = await runPageTurn("early_reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "none");
});
