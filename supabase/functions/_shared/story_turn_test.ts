import { assertEquals } from "jsr:@std/assert@1";
import { dropRepeatedEarlierText, fitToPage, mergeBibleCharacters, runStoryTurn, type StoryTurnDeps } from "./story_turn.ts";
import type { StoryBible } from "./schemas.ts";
import type { StoryModelOutput } from "./story_schema.ts";

function output(overrides: Partial<StoryModelOutput> = {}): StoryModelOutput {
  return {
    action: "append",
    pageText: "A friendly dragon shares a cookie.",
    artPrompt: "A friendly dragon sharing a cookie with a child.",
    breakSuggested: false,
    readingQuestion: "What does the dragon share?",
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

Deno.test("runStoryTurn fits an overlong page to the word limit instead of refusing it", async () => {
  const tooLong = Array(20).fill("word").join(" "); // 20 words > listener's 15-word cap
  const deps = depsFor([output({ action: "new_page", pageText: tooLong })], [true]);
  const result = await runStoryTurn("listener", 0, "", emptyBible, deps);
  assertEquals(result.page.text.split(" ").length, 15);
  assertEquals(result.action, "new_page");
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

Deno.test("an append that drops the page's existing words gets them back in front", async () => {
  const deps = depsFor([output({ pageText: "He waved the leaf." })], [true]);
  const result = await runStoryTurn("reader", 0, "Pip found a glowing leaf.", emptyBible, deps);
  assertEquals(result.action, "append");
  assertEquals(result.page.text, "Pip found a glowing leaf. He waved the leaf.");
});

Deno.test("an append that already starts with the page's words is left alone", async () => {
  const deps = depsFor([output({ pageText: "Pip found a glowing leaf. He waved it." })], [true]);
  const result = await runStoryTurn("reader", 0, "Pip found a glowing leaf.", emptyBible, deps);
  assertEquals(result.page.text, "Pip found a glowing leaf. He waved it.");
});

Deno.test("a new_page draft is for the next page index", async () => {
  const deps = depsFor([output({ action: "new_page", pageText: "The next morning, Pip woke up." })], [true]);
  const result = await runStoryTurn("reader", 2, "Pip slept under the stars.", emptyBible, deps);
  assertEquals(result.action, "new_page");
  assertEquals(result.page.index, 3);
  assertEquals(result.page.text, "The next morning, Pip woke up.");
});

Deno.test("dropRepeatedEarlierText strips a new page that restarts with the page before it", () => {
  const earlier = ["Maya the little blue dragon finds a shiny red kite in the meadow."];
  const repeated = output({
    action: "new_page",
    pageText: "Maya the little blue dragon finds a shiny red kite in the meadow. She smiles and lifts it high.",
  });
  assertEquals(dropRepeatedEarlierText(repeated, earlier).pageText, "She smiles and lifts it high.");
});

Deno.test("dropRepeatedEarlierText strips several earlier pages repeated in order, ignoring case and spacing", () => {
  const earlier = ["One day Maya flew.", "Then she  landed!"];
  const repeated = output({ pageText: "one day maya flew. Then she landed! And she slept." });
  assertEquals(dropRepeatedEarlierText(repeated, earlier).pageText, "And she slept.");
});

Deno.test("dropRepeatedEarlierText leaves a page alone when it doesn't repeat, or would be left empty", () => {
  const earlier = ["Maya flew."];
  assertEquals(dropRepeatedEarlierText(output({ pageText: "Maya landed softly." }), earlier).pageText, "Maya landed softly.");
  assertEquals(dropRepeatedEarlierText(output({ pageText: "Maya flew." }), earlier).pageText, "Maya flew.");
  assertEquals(dropRepeatedEarlierText(output({ action: "none", pageText: "Maya flew. More." }), earlier).pageText, "Maya flew. More.");
});

Deno.test("fitToPage moves a safe append that overflows the page onto a new page with only the new words", () => {
  const current = "Maya the dragon finds a red kite in the green meadow today.";
  const full = output({ action: "append", pageText: `${current} She lifts it up high into the sky.` });
  const fitted = fitToPage(full, current, "listener");
  assertEquals(fitted.action, "new_page");
  assertEquals(fitted.pageText, "She lifts it up high into the sky.");
});

Deno.test("fitToPage trims an overlong page to whole sentences within the limit", () => {
  const long = output({ action: "new_page", pageText: "Maya flies up. The kite flies too. They dance and spin and twirl around the sunny sky all day long." });
  assertEquals(fitToPage(long, "", "listener").pageText, "Maya flies up. The kite flies too.");
});

Deno.test("fitToPage cuts a single overlong sentence at the word limit", () => {
  const words = Array.from({ length: 20 }, (_, i) => `w${i}`).join(" ");
  const fitted = fitToPage(output({ action: "revise_current", pageText: `${words}.` }), "", "listener");
  assertEquals(fitted.pageText.split(" ").length, 15);
  assertEquals(fitted.pageText.endsWith("."), true);
});

Deno.test("fitToPage leaves a page within the limit alone", () => {
  const ok = output({ action: "append", pageText: "Maya flies." });
  assertEquals(fitToPage(ok, "", "listener"), ok);
});

Deno.test("runStoryTurn turns a full page into a new page instead of refusing it", async () => {
  const current = "Maya the dragon finds a red kite in the green meadow today.";
  const deps = depsFor([output({ action: "append", pageText: `${current} She lifts it up high into the sky.` })], [true]);
  const data = await runStoryTurn("listener", 0, current, emptyBible, deps);
  assertEquals(data.action, "new_page");
  assertEquals(data.page.index, 1);
  assertEquals(data.page.text, "She lifts it up high into the sky.");
  assertEquals(data.parentNote, null);
});

Deno.test("runStoryTurn returns the page's reading question and runs it past the safety gate", async () => {
  const checked: string[] = [];
  const deps: StoryTurnDeps = {
    callModel: async () => ({ output: output({ readingQuestion: "  Who shares the cookie?  " }), modelMs: 5 }),
    safety: {
      moderateText: async (text: string) => {
        checked.push(text);
        return { flagged: false, categories: [] };
      },
      checkRubric: async () => ({ safe: true, reason: "" }),
    },
  };
  const result = await runStoryTurn("early_reader", 0, "", emptyBible, deps);
  assertEquals(result.page.question, "Who shares the cookie?");
  assertEquals(checked.some((text) => text.includes("Who shares the cookie?")), true);
});
