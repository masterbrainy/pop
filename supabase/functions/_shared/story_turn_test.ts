import { assertEquals } from "jsr:@std/assert@1";
import { mergeBibleCharacters, runStoryTurn, type StoryTurnDeps } from "./story_turn.ts";
import type { StoryBible } from "./schemas.ts";
import type { StoryModelOutput } from "./story_schema.ts";

function output(overrides: Partial<StoryModelOutput> = {}): StoryModelOutput {
  return {
    action: "append",
    pageText: "A friendly dragon shares a cookie.",
    artPrompt: "A friendly dragon sharing a cookie with a child.",
    breakSuggested: false,
    bibleTitle: null,
    bibleSetting: "A cozy meadow",
    bibleCharacters: [],
    bibleDirections: [],
    parentNote: null,
    ...overrides,
  };
}

const emptyBible: StoryBible = { title: null, setting: "", characters: [], directions: [] };

function depsFor(outputs: StoryModelOutput[], safe: boolean[]): StoryTurnDeps {
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

Deno.test("runStoryTurn returns the first attempt when it passes the gate", async () => {
  const deps = depsFor([output()], [true]);
  const result = await runStoryTurn("early_reader", 1, "", emptyBible, deps);
  assertEquals(result.action, "append");
  assertEquals(result.page.text, "A friendly dragon shares a cookie.");
  assertEquals(result.parentNote, null);
});

Deno.test("runStoryTurn rewrites once when the first attempt fails the rubric, and returns the rewrite", async () => {
  const deps = depsFor(
    [output({ pageText: "Something scary happens." }), output({ pageText: "Something gentle happens." })],
    [false, true],
  );
  const result = await runStoryTurn("early_reader", 1, "", emptyBible, deps);
  assertEquals(result.page.text, "Something gentle happens.");
  assertEquals(result.parentNote, null);
});

Deno.test("runStoryTurn falls back to none with a gentle parentNote after two failed attempts", async () => {
  const deps = depsFor(
    [output({ pageText: "Bad one" }), output({ pageText: "Still bad" })],
    [false, false],
  );
  const result = await runStoryTurn("listener", 2, "prior draft", emptyBible, deps);
  assertEquals(result.action, "none");
  assertEquals(result.page.index, 2);
  assertEquals(result.page.text, "prior draft");
  assertEquals(result.bible, emptyBible);
  assertEquals(result.parentNote !== null, true);
});

Deno.test("runStoryTurn treats action 'none' from the model as trivially safe (no rewrite)", async () => {
  let calls = 0;
  const deps: StoryTurnDeps = {
    callModel: async () => {
      calls++;
      return { output: output({ action: "none", pageText: "", artPrompt: "", parentNote: "Let's try something else." }), modelMs: 5 };
    },
    safety: {
      moderateText: async () => ({ flagged: false, categories: [] }),
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
  };
  const result = await runStoryTurn("reader", 0, "", emptyBible, deps);
  assertEquals(calls, 1);
  assertEquals(result.action, "none");
  assertEquals(result.parentNote, "Let's try something else.");
});

Deno.test("runStoryTurn rewrites when the page exceeds the reading level's word limit, even if the rubric passes", async () => {
  const tooLong = Array(20).fill("word").join(" "); // 20 words > listener's 15-word cap
  const deps = depsFor(
    [output({ pageText: tooLong }), output({ pageText: "Short and sweet." })],
    [true, true],
  );
  const result = await runStoryTurn("listener", 0, "", emptyBible, deps);
  assertEquals(result.page.text, "Short and sweet.");
});

Deno.test("runStoryTurn maps bibleCharacters and preserves existing referencePath by id", async () => {
  const bible: StoryBible = {
    title: null,
    setting: "",
    characters: [{ id: "c1", name: "Rex", description: "a dinosaur", referencePath: "u/b/character-c1-v1.png" }],
    directions: [],
  };
  const deps = depsFor(
    [output({
      bibleCharacters: [
        { id: "c1", name: "Rex", description: "a friendly green dinosaur" },
        { id: "c2", name: "Maya", description: "a curious kid" },
      ],
    })],
    [true],
  );
  const result = await runStoryTurn("reader", 0, "", bible, deps);
  assertEquals(result.bible.characters, [
    { id: "c1", name: "Rex", description: "a friendly green dinosaur", referencePath: "u/b/character-c1-v1.png" },
    { id: "c2", name: "Maya", description: "a curious kid", referencePath: null },
  ]);
});

Deno.test("mergeBibleCharacters returns null referencePath for a brand-new bible", () => {
  const result = mergeBibleCharacters([], [{ id: "c1", name: "Rex", description: "a dinosaur" }]);
  assertEquals(result, [{ id: "c1", name: "Rex", description: "a dinosaur", referencePath: null }]);
});
