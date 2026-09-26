import { assert, assertFalse } from "jsr:@std/assert@1";
import {
  buildStoryPageSystemPrompt,
  buildStoryPathSystemPrompt,
  buildTitlePrompt,
  type StoryPagePromptInput,
  type StoryPathPromptInput,
} from "./story_prompt.ts";

Deno.test("buildTitlePrompt orders pages by index and includes the setting and first name", () => {
  const prompt = buildTitlePrompt(
    { title: null, setting: "a quiet meadow", characters: [], directions: [], path: [] },
    [{ index: 1, text: "Page two text" }, { index: 0, text: "Page one text" }],
    "Maya",
  );
  const indexOfPageOne = prompt.indexOf("Page one text");
  const indexOfPageTwo = prompt.indexOf("Page two text");
  assert(indexOfPageOne < indexOfPageTwo);
  assert(prompt.includes("Maya"));
  assert(prompt.includes("a quiet meadow"));
});

function basePathInput(overrides: Partial<StoryPathPromptInput> = {}): StoryPathPromptInput {
  return {
    kid: { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: [] },
    pages: [],
    index: 0,
    input: null,
    ...overrides,
  };
}

Deno.test("buildStoryPathSystemPrompt asks the model to plan about 5-8 beats ending the story", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("5 to 8"));
  assert(prompt.toLowerCase().includes("end the story"));
});

Deno.test("buildStoryPathSystemPrompt lists earlier beats as fixed and never to change, at the start with none", () => {
  const withStart = buildStoryPathSystemPrompt(basePathInput());
  assertFalse(withStart.includes("never change these"));

  const withKept = buildStoryPathSystemPrompt(
    basePathInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] }, index: 1 }),
  );
  assert(withKept.includes("never change these"));
  assert(withKept.includes("Beat 0"));
});

Deno.test("buildStoryPathSystemPrompt folds a direction into the prompt and asks to re-plan from index on, only when input is present", () => {
  const withoutDirection = buildStoryPathSystemPrompt(basePathInput());
  assert(withoutDirection.includes("Plan the path from the brief"));

  const withDirection = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "typed", speaker: "parent", text: "wake the dragon up" } }),
  );
  assert(withDirection.includes("wake the dragon up"));
  assert(withDirection.includes("re-plan the path"));
});

Deno.test("buildStoryPathSystemPrompt never omits the personal-details or safety rubric instructions", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("surnames"));
  assert(prompt.includes("Kid-safety rubric"));
});

// R-42/ending-eval product rule: a direction that explicitly asks to end the
// story now overrides the usual "about 5 to 8 beats" guidance for that turn.
Deno.test("buildStoryPathSystemPrompt tells the model to end at this page when the direction asks to end now", () => {
  const withEndRequest = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      input: { kind: "typed", speaker: "parent", text: "Let's finish the story here with a proper ending." },
    }),
  );
  assert(withEndRequest.includes("make page 1 the very last beat"));
  assert(withEndRequest.includes('set "isEnding" to true'));
});

Deno.test("buildStoryPathSystemPrompt does not add the end-now instruction for an ordinary direction", () => {
  const withOrdinaryDirection = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "typed", speaker: "parent", text: "wake the dragon up" } }),
  );
  assertFalse(withOrdinaryDirection.includes("the very last beat"));
});

Deno.test("buildStoryPathSystemPrompt suggests concrete closing images for the path's last beat generally", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("safe and happy"));
  assert(prompt.includes("drifting off to sleep"));
});

Deno.test("buildStoryPathSystemPrompt gives the prescriptive ending-close instruction when the direction asks to end now", () => {
  const withEndRequest = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      kid: { firstName: "Maya", readingLevel: "reader", interests: ["dinosaurs"] },
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      input: { kind: "typed", speaker: "parent", text: "Let's finish the story here with a proper ending." },
    }),
  );
  assert(withEndRequest.includes("unmistakable close"));
  assert(withEndRequest.includes("safe and back home"));
  assert(withEndRequest.includes('the words "The end."'));
});

Deno.test("buildStoryPathSystemPrompt tells the model to write only in the brief's language", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("only in English"));
  assert(prompt.includes("Never mix in a word, phrase or script from any other language"));
});

function basePageInput(overrides: Partial<StoryPagePromptInput> = {}): StoryPagePromptInput {
  return {
    kid: { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Maya finds a red kite in the meadow."] },
    pages: [],
    index: 0,
    ...overrides,
  };
}

Deno.test("buildStoryPageSystemPrompt writes from the existing beat at bible.path[index]", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("Maya finds a red kite in the meadow."));
  assert(prompt.includes("do not invent a different moment"));
});

Deno.test("buildStoryPageSystemPrompt never omits the personal-details or safety rubric instructions", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("surnames"));
  assert(prompt.includes("Kid-safety rubric"));
});

Deno.test("buildStoryPageSystemPrompt tells the model to write only in the brief's language", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("only in English"));
  assert(prompt.includes("Never mix in a word, phrase or script from any other language"));
});

Deno.test("buildStoryPageSystemPrompt tells the model to write a clear ending only on the path's last index", () => {
  const notLastPage = buildStoryPageSystemPrompt(
    basePageInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] }, index: 0 }),
  );
  assertFalse(notLastPage.includes("path's last page"));

  const lastPage = buildStoryPageSystemPrompt(
    basePageInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] }, index: 1 }),
  );
  assert(lastPage.includes("path's last page"));
  assert(lastPage.includes("unmistakable close"));
  assert(lastPage.includes('the words "The end."'));
});

Deno.test("buildStoryPageSystemPrompt asks for one of the eval's exact closing phrases at the reader level", () => {
  const lastPage = buildStoryPageSystemPrompt(
    basePageInput({
      kid: { firstName: "Maya", readingLevel: "reader", interests: ["dinosaurs"] },
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] },
      index: 1,
    }),
  );
  assert(lastPage.includes("safe and back home"));
  assert(lastPage.includes("drifted off to sleep"));
});

Deno.test("buildStoryPathSystemPrompt steers away from a branded interest or direction by name", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    brief: { interests: ["Lego", "dinosaurs"], realMoment: null, teach: null, language: "en" },
    input: { kind: "typed", speaker: "kid", text: "put Elsa in it" },
  }));
  assert(prompt.includes("Never use these brand or character names: lego, elsa."));
});

Deno.test("buildStoryPathSystemPrompt adds no brand line when nothing branded came in", () => {
  assertFalse(buildStoryPathSystemPrompt(basePathInput()).includes("Never use these brand or character names"));
});

Deno.test("buildStoryPageSystemPrompt steers away from a branded name in the interests or the planned beat", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    brief: { interests: ["Paw Patrol"], realMoment: null, teach: null, language: "en" },
  }));
  assert(prompt.includes("Never use these brand or character names: paw patrol."));
});

Deno.test("buildStoryPathSystemPrompt never lists the kid's own name as a brand", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Elsa", readingLevel: "early_reader", interests: ["snow"] },
  }));
  assertFalse(prompt.includes("Never use these brand or character names"));
});
