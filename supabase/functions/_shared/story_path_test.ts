import { assertEquals } from "jsr:@std/assert@1";
import { planNewPath, runPageTurn, runPathTurn, type RunPageTurnDeps, type RunPathTurnDeps } from "./story_path.ts";
import type { InputSafetyVerdict } from "./input_safety.ts";
import type { StoryBible } from "./schemas.ts";
import type { ModelQuestion, StoryPageModelOutput, StoryPathModelOutput } from "./story_path_schema.ts";

const DEFAULT_ASK = "Will the kite fly to the tree or the pond?";

const defaultQuestion: ModelQuestion = {
  ask: DEFAULT_ASK,
  kind: "choice",
  choices: [
    { label: "The tree", symbol: "tree.fill", direction: "The kite drifts into the old oak tree.", followsPath: true },
    { label: "The pond", symbol: "drop.fill", direction: "The kite lands softly on the pond.", followsPath: false },
  ],
};

const safeBrief = async (): Promise<InputSafetyVerdict> => ({ blocked: false, parentNote: null, refusal: null });

/** The question gate's rubric call starts with the question's ask; the page gate's never does. */
function isQuestionGateCall(combined: string): boolean {
  return combined.startsWith(DEFAULT_ASK);
}

function pathOutput(overrides: Partial<StoryPathModelOutput> = {}): StoryPathModelOutput {
  return {
    path: ["Sara finds a red kite in the meadow.", "Sara falls asleep holding the kite. The end."],
    isEnding: false,
    pageText: "Sara finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    question: defaultQuestion,
    bibleTitle: null,
    bibleSetting: "A sunny meadow",
    bibleCharacters: [{ id: "sara", name: "Sara", description: "a curious kid" }],
    bibleDirections: [],
    parentNote: null,
    ...overrides,
  };
}

function pageOutput(overrides: Partial<StoryPageModelOutput> = {}): StoryPageModelOutput {
  return {
    pageText: "Sara finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    question: defaultQuestion,
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

/** `safe[i]` is the page gate's rubric verdict for attempt i; the question gate always passes. */
function rubricBySafeList(safe: boolean[]) {
  let pageGateCall = 0;
  return async (combined: string) => {
    if (isQuestionGateCall(combined)) return { safe: true, reason: "" };
    const verdict = safe[pageGateCall++];
    return { safe: verdict, reason: verdict ? "" : "too scary" };
  };
}

function pathDepsFor(outputs: StoryPathModelOutput[], safe: boolean[]): RunPathTurnDeps {
  let modelCall = 0;
  return {
    callModel: async () => ({ output: outputs[modelCall++], modelMs: 10 }),
    safety: {
      moderateText: async () => ({ flagged: false, categories: [] }),
      checkRubric: rubricBySafeList(safe),
    },
    inputSafety: safeInputSafety(),
    checkBrief: safeBrief,
  };
}

function pageDepsFor(outputs: StoryPageModelOutput[], safe: boolean[]): RunPageTurnDeps {
  let modelCall = 0;
  return {
    callModel: async () => ({ output: outputs[modelCall++], modelMs: 10 }),
    safety: {
      moderateText: async () => ({ flagged: false, categories: [] }),
      checkRubric: rubricBySafeList(safe),
    },
    checkBrief: safeBrief,
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
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.index, 0);
  assertEquals(result.bible.path, ["Sara finds a red kite in the meadow.", "Sara falls asleep holding the kite. The end."]);
  assertEquals(result.parentNote, null);
});

Deno.test("runPathTurn keeps beats before index when re-planning from a direction", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Sara finds a red kite in the meadow."] };
  const deps = pathDepsFor(
    [pathOutput({ path: ["Sara wakes the sleepy dragon.", "The dragon and Sara nap together. The end."] })],
    [true],
  );
  const result = await runPathTurn("early_reader", 1, bible, "Sara", "en", { text: "wake the dragon up", speaker: "parent" }, deps);
  assertEquals(result.bible.path, [
    "Sara finds a red kite in the meadow.",
    "Sara wakes the sleepy dragon.",
    "The dragon and Sara nap together. The end.",
  ]);
});

Deno.test("runPathTurn reports isEnding for the path's last beat", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Sara falls asleep. The end."] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPathTurn reports isEnding false for a beat that isn't last", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Beat one", "Beat two, the end"] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn rewrites once when the first attempt fails the gate, then returns the rewrite", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Something scary happens." }), pathOutput({ pageText: "Something gentle happens." })],
    [false, true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.page.text, "Something gentle happens.");
});

Deno.test("runPathTurn falls back to none with a gentle parentNote after two failed attempts", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Bad one" }), pathOutput({ pageText: "Still bad" })],
    [false, false],
  );
  const result = await runPathTurn("listener", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "none");
  assertEquals(result.bible, emptyBible);
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPathTurn blocks a flagged direction from a kid before any model call, returning none with refusal 'real_harm'", async () => {
  let modelCalled = false;
  const deps: RunPathTurnDeps = {
    checkBrief: safeBrief,
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
  const result = await runPathTurn("early_reader", 1, bible, "Sara", "en", { text: "unsafe direction", speaker: "kid" }, deps);
  assertEquals(result.action, "none");
  assertEquals(result.bible, bible);
  assertEquals(modelCalled, false);
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "real_harm");
});

Deno.test("runPathTurn blocks a flagged direction from a parent when the direction-safety second opinion also says unsafe, returning none with refusal 'unsafe'", async () => {
  const deps: RunPathTurnDeps = {
    checkBrief: safeBrief,
    callModel: async () => ({ output: pathOutput(), modelMs: 10 }),
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
    inputSafety: {
      moderateText: async () => ({ flagged: true, categories: ["violence"] }),
      checkRealHarm: async () => ({ safe: true, reason: "" }),
      checkDirectionSafety: async () => ({ safe: false, reason: "genuinely unsafe" }),
    },
  };
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Sara", "en", { text: "unsafe direction", speaker: "parent" }, deps);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPathTurn returns refusal null on a successful page", async () => {
  const deps = pathDepsFor([pathOutput()], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
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
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "A friendly fox is nearby in the meadow.");
});

Deno.test("runPathTurn fails the output gate on a branded character, then accepts an original one", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({ pageText: "Mickey Mouse and Sara fly a kite." }),
      pathOutput({ pageText: "A round-eared mouse named Pip and Sara fly a kite." }),
    ],
    [true, true],
  );
  const result = await runPathTurn("listener", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "A round-eared mouse named Pip and Sara fly a kite.");
});

Deno.test("runPathTurn refuses when the rewrite still names a branded character", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({ pageText: "Mickey Mouse and Sara fly a kite." }),
      pathOutput({ pageText: "Sara and her friend from Cocomelon fly a kite." }),
    ],
    [true, true],
  );
  const result = await runPathTurn("listener", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "none");
});

// --- runPathTurn (R-42) ---

Deno.test("runPathTurn allows the kid's own non-Latin name in an 'en' story", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "李明 finds a red kite in the meadow.", path: ["李明 finds a red kite in the meadow."] })],
    [true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "李明", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "李明 finds a red kite in the meadow. The end."); // the path's last page
});

Deno.test("runPathTurn allows a bible character's non-Latin name in an 'en' story", async () => {
  const deps = pathDepsFor(
    [
      pathOutput({
        pageText: "Sara waved to her friend Дима by the lake.",
        bibleCharacters: [
          { id: "sara", name: "Sara", description: "a curious kid" },
          { id: "dima", name: "Дима", description: "Sara's friend" },
        ],
      }),
    ],
    [true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "Sara waved to her friend Дима by the lake.");
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
    checkBrief: safeBrief,
    callModel: async () => ({ output: pathOutput({ bibleTitle: "flagged title" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged title", categories: text === "flagged title" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
    inputSafety: safeInputSafety(),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.action, "none");
});

Deno.test("runPathTurn gates a flagged successful parentNote even when the page text itself is safe", async () => {
  const deps: RunPathTurnDeps = {
    checkBrief: safeBrief,
    callModel: async () => ({ output: pathOutput({ parentNote: "flagged note" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged note", categories: text === "flagged note" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
    inputSafety: safeInputSafety(),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
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
    "Sara",
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
    "Sara",
    "en",
    { text: "wake the dragon up", speaker: "parent" },
    deps,
  );
  assertEquals(result.bible.path, ["Beat 0", "Beat 1", "Beat 2, the end"]);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn never ends on page 1 because the opening idea mentions an ending", async () => {
  // The first prompt (index 0, nothing shown, input set) plans the whole story;
  // an opening like "…and we end the story with a bedtime hug" describes the
  // story's close, not a request to stop now.
  const deps = pathDepsFor(
    [pathOutput({ path: ["Beat 0", "Beat 1", "Beat 2, a bedtime hug"], isEnding: false })],
    [true],
  );
  const result = await runPathTurn(
    "early_reader",
    0,
    emptyBible,
    "Maya",
    "en",
    { text: "a bunny who finds a lost star, and we end the story with a bedtime hug", speaker: "parent" },
    deps,
    [],
  );
  assertEquals(result.bible.path, ["Beat 0", "Beat 1", "Beat 2, a bedtime hug"]);
  assertEquals(result.page.isEnding, false);
});

Deno.test("runPathTurn still forces the ending for an end request on page 0 once that page has been shown", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Beat 0", "Beat 1"], isEnding: false })], [true]);
  const result = await runPathTurn(
    "early_reader",
    0,
    emptyBible,
    "Maya",
    "en",
    { text: "Let's finish the story here with a proper ending.", speaker: "parent" },
    deps,
    ["Maya finds a red kite in the meadow."],
  );
  assertEquals(result.bible.path, ["Beat 0"]);
  assertEquals(result.page.isEnding, true);
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
    checkBrief: safeBrief,
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
  const bible: StoryBible = { ...emptyBible, path: ["Sara finds a red kite in the meadow.", "Sara falls asleep. The end."] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.index, 0);
  assertEquals(result.page.isEnding, false);
  assertEquals(result.bible, bible);
  assertEquals(result.refusal, null);
});

Deno.test("runPageTurn reports isEnding true for the path's last index", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1, the end"] };
  const deps = pageDepsFor([pageOutput()], [true]);
  const result = await runPageTurn("early_reader", 1, bible, "Sara", "en", deps);
  assertEquals(result.page.isEnding, true);
});

Deno.test("runPageTurn past the path's end returns none with no model call", async () => {
  let modelCalled = false;
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps: RunPageTurnDeps = {
    checkBrief: safeBrief,
    callModel: async () => {
      modelCalled = true;
      return { output: pageOutput(), modelMs: 10 };
    },
    safety: { moderateText: async () => ({ flagged: false, categories: [] }), checkRubric: async () => ({ safe: true, reason: "" }) },
  };
  const result = await runPageTurn("early_reader", 1, bible, "Sara", "en", deps);
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
  const result = await runPageTurn("early_reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.page.text, "Something gentle. The end."); // the path's last page
});

Deno.test("runPageTurn falls back to none after two failed attempts", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor([pageOutput({ pageText: "Bad" }), pageOutput({ pageText: "Still bad" })], [false, false]);
  const result = await runPageTurn("listener", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote !== null, true);
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPageTurn drops a page that retells an earlier shown page", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1"] };
  const earlier = ["Sara the little blue dragon finds a shiny red kite in the meadow."];
  const deps = pageDepsFor(
    [pageOutput({ pageText: "Sara the little blue dragon finds a shiny red kite in the meadow. She smiles and lifts it high." })],
    [true],
  );
  const result = await runPageTurn("reader", 1, bible, "Sara", "en", deps, earlier);
  assertEquals(result.page.text, "She smiles and lifts it high. The end."); // the path's last page
});

Deno.test("runPageTurn trims an overlong page to the reading level's word limit instead of refusing it", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1"] }; // not the ending page, which may run 2 words over
  const tooLong = Array(20).fill("word").join(" "); // 20 words > listener's 15-word cap
  const deps = pageDepsFor([pageOutput({ pageText: tooLong })], [true]);
  const result = await runPageTurn("listener", 0, bible, "Sara", "en", deps);
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
  const result = await runPageTurn("reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "A friendly fox is nearby, and both look surprised. The end."); // the path's last page
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
  const result = await runPageTurn("reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "none");
  assertEquals(result.refusal, "unsafe");
});

Deno.test("runPageTurn never checks language for a non-'en' brief", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps = pageDepsFor([pageOutput({ pageText: "Un renard sympathique est рядом." })], [true]);
  const result = await runPageTurn("reader", 0, bible, "Sara", "fr", deps);
  assertEquals(result.action, "page");
});

// --- runPageTurn (R-42) ---

Deno.test("runPageTurn allows the kid's own non-Latin name in an 'en' story", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["李明 finds a red kite in the meadow."] };
  const deps = pageDepsFor([pageOutput({ pageText: "李明 finds a red kite in the meadow." })], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "李明", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "李明 finds a red kite in the meadow. The end."); // the path's last page
});

Deno.test("runPageTurn allows a bible character's non-Latin name in an 'en' story", async () => {
  const bible: StoryBible = {
    ...emptyBible,
    characters: [{ id: "dima", name: "Дима", description: "Sara's friend", referencePath: null }],
    path: ["Sara waved to her friend Дима by the lake."],
  };
  const deps = pageDepsFor([pageOutput({ pageText: "Sara waved to her friend Дима by the lake." })], [true]);
  const result = await runPageTurn("early_reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "Sara waved to her friend Дима by the lake. The end."); // the path's last page
});

Deno.test("runPageTurn gates a flagged successful parentNote even when the page text itself is safe", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const deps: RunPageTurnDeps = {
    checkBrief: safeBrief,
    callModel: async () => ({ output: pageOutput({ parentNote: "flagged note" }), modelMs: 10 }),
    safety: {
      moderateText: async (text) => ({ flagged: text === "flagged note", categories: text === "flagged note" ? ["unsafe"] : [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
  };
  const result = await runPageTurn("early_reader", 0, bible, "Sara", "en", deps);
  assertEquals(result.action, "none");
});

Deno.test("runPathTurn closes the path's last page with 'The end.' (S14)", async () => {
  const deps = pathDepsFor(
    [pathOutput({ pageText: "Sara and the fox curl up under the stars.", path: ["Sara and the fox curl up under the stars."] })],
    [true],
  );
  const result = await runPathTurn("early_reader", 0, emptyBible, "Sara", "en", null, deps);
  assertEquals(result.page.isEnding, true);
  assertEquals(result.page.text, "Sara and the fox curl up under the stars. The end.");
});

// --- IMP-25: the page's question and choices ---

/** Safety deps whose moderation flags exactly the texts in `flagged`; the rubric always passes. */
function flaggingSafety(flagged: string[]) {
  return {
    moderateText: async (text: string) => ({ flagged: flagged.includes(text), categories: flagged.includes(text) ? ["x"] : [] }),
    checkRubric: async () => ({ safe: true, reason: "" }),
  };
}

Deno.test("runPathTurn ships the page's question with its kind and choices", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Beat 0", "Beat 1", "Beat 2"] })], [true]);
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.page.question, DEFAULT_ASK);
  assertEquals(result.page.questionKind, "choice");
  assertEquals(result.page.choices.map((c) => c.label), ["The tree", "The pond"]);
  assertEquals(result.page.choices.map((c) => c.followsPath), [true, false]);
});

Deno.test("runPathTurn drops only the question when a choice fails its own gate; the page still ships", async () => {
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput({ path: ["Beat 0", "Beat 1"] })], [true]),
    safety: flaggingSafety(["The kite lands softly on the pond."]),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(result.page.text, "Maya finds a red kite in the meadow.");
  assertEquals(result.page.question, "");
  assertEquals("questionKind" in result.page, false);
  assertEquals(result.page.choices, []);
});

Deno.test("runPathTurn never lets a flagged question sink the page (no rewrite for the question alone)", async () => {
  let modelCalls = 0;
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput(), pathOutput()], [true, true]),
    callModel: async () => {
      modelCalls += 1;
      return { output: pathOutput({ path: ["Beat 0", "Beat 1"] }), modelMs: 10 };
    },
    safety: flaggingSafety([DEFAULT_ASK]),
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "page");
  assertEquals(modelCalls, 1);
  assertEquals(result.page.question, "");
});

Deno.test("runPathTurn drops a question that leaks a foreign script or names a brand", async () => {
  const foreign = pathOutput({ path: ["Beat 0", "Beat 1"], question: { ...defaultQuestion, ask: "Куда полетит kite?" } });
  const branded = pathOutput({
    path: ["Beat 0", "Beat 1"],
    question: {
      ...defaultQuestion,
      choices: [defaultQuestion.choices[0], { ...defaultQuestion.choices[1], label: "Ask Elsa" }],
    },
  });
  for (const output of [foreign, branded]) {
    const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, pathDepsFor([output], [true]));
    assertEquals(result.action, "page");
    assertEquals(result.page.question, "");
    assertEquals(result.page.choices, []);
  }
});

Deno.test("runPathTurn uses and gates the rewrite attempt's question when the first page failed", async () => {
  const secondQuestion: ModelQuestion = {
    ...defaultQuestion,
    choices: [defaultQuestion.choices[0], { ...defaultQuestion.choices[1], direction: "The kite hides in a scary cave." }],
  };
  const deps: RunPathTurnDeps = {
    ...pathDepsFor(
      [
        pathOutput({ pageText: "Something scary happens.", path: ["Beat 0", "Beat 1"] }),
        pathOutput({ pageText: "Something gentle happens.", path: ["Beat 0", "Beat 1"], question: secondQuestion }),
      ],
      [false, true],
    ),
  };
  const moderation = flaggingSafety(["The kite hides in a scary cave."]).moderateText;
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, {
    ...deps,
    safety: { ...deps.safety, moderateText: moderation },
  });
  assertEquals(result.page.text, "Something gentle happens.");
  assertEquals(result.page.question, "");
  assertEquals(result.page.choices, []);
});

Deno.test("runPathTurn applies the question plan with the real planned path: a listener's ending is talk-only", async () => {
  const deps = pathDepsFor([pathOutput({ path: ["Maya falls asleep. The end."] })], [true]);
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0"] };
  const result = await runPathTurn("listener", 1, bible, "Maya", "en", { text: "time for bed", speaker: "parent" }, deps);
  assertEquals(result.page.isEnding, true);
  assertEquals(result.page.questionKind, "talkOnly");
  assertEquals(result.page.choices, []);
  assertEquals(result.page.question, DEFAULT_ASK);
});

Deno.test("runPathTurn gives a listener talk-only on page 0 and 2 choices on page 1", async () => {
  const page0 = await runPathTurn("listener", 0, emptyBible, "Maya", "en", null, pathDepsFor([pathOutput({ path: ["B0", "B1", "B2"] })], [true]));
  assertEquals(page0.page.questionKind, "talkOnly");
  assertEquals(page0.page.choices, []);

  const bible: StoryBible = { ...emptyBible, path: ["B0"] };
  const page1 = await runPathTurn(
    "listener",
    1,
    bible,
    "Maya",
    "en",
    { text: "the kite flies away", speaker: "parent" },
    pathDepsFor([pathOutput({ path: ["B1", "B2", "B3"] })], [true]),
  );
  assertEquals(page1.page.questionKind, "choice");
  assertEquals(page1.page.choices.length, 2);
});

Deno.test("runPageTurn ships a normalized question and drops a flagged one without refusing the page", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1", "Beat 2"] };
  const ok = await runPageTurn("reader", 0, bible, "Maya", "en", pageDepsFor([pageOutput()], [true]));
  assertEquals(ok.page.questionKind, "open");
  assertEquals(ok.page.choices.length, 2);

  const flagged = await runPageTurn("reader", 0, bible, "Maya", "en", {
    ...pageDepsFor([pageOutput()], [true]),
    safety: flaggingSafety(["The tree"]),
  });
  assertEquals(flagged.action, "page");
  assertEquals(flagged.page.question, "");
  assertEquals(flagged.page.choices, []);
});

Deno.test("runPageTurn's ending page is talk-only", async () => {
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1"] };
  const result = await runPageTurn("early_reader", 1, bible, "Maya", "en", pageDepsFor([pageOutput()], [true]));
  assertEquals(result.page.questionKind, "talkOnly");
  assertEquals(result.page.choices, []);
});

Deno.test("a refused page carries an empty question and no choices", async () => {
  const deps = pathDepsFor([pathOutput({ pageText: "Bad one" }), pathOutput({ pageText: "Still bad" })], [false, false]);
  const result = await runPathTurn("listener", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "none");
  assertEquals(result.page.question, "");
  assertEquals(result.page.choices, []);
  assertEquals("questionKind" in result.page, false);
});

// --- IMP-25: a tapped choice as input ---

Deno.test("runPathTurn moderates a tapped choice only (no real-harm rubric), then re-plans from it", async () => {
  let realHarmCalled = false;
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput({ path: ["The dragon looks under the bed.", "B2"] })], [true]),
    inputSafety: {
      ...safeInputSafety(),
      checkRealHarm: async () => {
        realHarmCalled = true;
        return { safe: true, reason: "" };
      },
    },
  };
  const bible: StoryBible = { ...emptyBible, path: ["B0"] };
  const result = await runPathTurn("early_reader", 1, bible, "Maya", "en", { text: "The dragon looks under the bed.", speaker: "kid", kind: "choice" }, deps);
  assertEquals(result.action, "page");
  assertEquals(realHarmCalled, false);
});

// --- IMP-24: brief safety runs before any model call ---

const blockedBrief = async (): Promise<InputSafetyVerdict> => ({ blocked: true, parentNote: "brief note", refusal: "unsafe" });

Deno.test("runPathTurn refuses an unsafe brief before any model call", async () => {
  let modelCalled = false;
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput()], [true]),
    callModel: async () => {
      modelCalled = true;
      return { output: pathOutput(), modelMs: 10 };
    },
    checkBrief: blockedBrief,
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", null, deps);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote, "brief note");
  assertEquals(result.refusal, "unsafe");
  assertEquals(modelCalled, false);
});

Deno.test("runPathTurn checks the brief and the direction together, both before the model", async () => {
  const order: string[] = [];
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput()], [true]),
    callModel: async () => {
      order.push("model");
      return { output: pathOutput(), modelMs: 10 };
    },
    checkBrief: async () => {
      order.push("brief");
      return { blocked: false, parentNote: null, refusal: null };
    },
    inputSafety: {
      ...safeInputSafety(),
      moderateText: async () => {
        order.push("direction");
        return { flagged: false, categories: [] };
      },
    },
  };
  await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", { text: "add a puppy", speaker: "parent" }, deps);
  assertEquals(order.slice(0, 2).sort(), ["brief", "direction"]);
  assertEquals(order[2], "model");
});

Deno.test("runPathTurn prefers the brief's real-harm verdict over the direction's generic one", async () => {
  const deps: RunPathTurnDeps = {
    ...pathDepsFor([pathOutput()], [true]),
    checkBrief: async () => ({ blocked: true, parentNote: "real harm note", refusal: "real_harm" }),
    inputSafety: {
      ...safeInputSafety(),
      moderateText: async () => ({ flagged: true, categories: ["violence"] }),
      checkDirectionSafety: async () => ({ safe: false, reason: "unsafe" }),
    },
  };
  const result = await runPathTurn("early_reader", 0, emptyBible, "Maya", "en", { text: "something", speaker: "parent" }, deps);
  assertEquals(result.refusal, "real_harm");
  assertEquals(result.parentNote, "real harm note");
});

Deno.test("runPageTurn refuses an unsafe brief before any model call", async () => {
  let modelCalled = false;
  const bible: StoryBible = { ...emptyBible, path: ["Beat 0", "Beat 1"] };
  const deps: RunPageTurnDeps = {
    ...pageDepsFor([pageOutput()], [true]),
    callModel: async () => {
      modelCalled = true;
      return { output: pageOutput(), modelMs: 10 };
    },
    checkBrief: blockedBrief,
  };
  const result = await runPageTurn("early_reader", 0, bible, "Maya", "en", deps);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote, "brief note");
  assertEquals(modelCalled, false);
});
