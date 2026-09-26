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

  // A later direction: page 0 is already shown, so this re-plans from page 1.
  const withDirection = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      pages: [{ index: 0, text: "Maya finds a sleeping dragon." }],
      input: { kind: "typed", speaker: "parent", text: "wake the dragon up" },
    }),
  );
  assert(withDirection.includes("wake the dragon up"));
  assert(withDirection.includes("re-plan the path from page 1 on"));
});

// The app writes page 1 only once the parent speaks or types the first prompt:
// index 0, nothing shown yet, and input set. That's the story's opening idea,
// not a mid-story direction.
Deno.test("buildStoryPathSystemPrompt plans the whole path from the parent's opening idea, with the brief as background", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "speech", speaker: "parent", text: "a dragon who is scared of the dark" } }),
  );
  assert(prompt.includes(
    'The parent\'s opening idea for the story: "a dragon who is scared of the dark". Plan the whole path from it, with the brief as background.',
  ));
  assert(prompt.includes("Fold this opening idea into the bible's directions so it carries into every later page."));
  assertFalse(prompt.includes("A direction just came in"));
  assertFalse(prompt.includes("re-plan the path"));
  assertFalse(prompt.includes("Plan the path from the brief above."));
});

Deno.test("buildStoryPathSystemPrompt names the kid when the opening idea is the kid's", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "speech", speaker: "kid", text: "a unicorn at the beach" } }),
  );
  assert(prompt.includes('Maya\'s opening idea for the story: "a unicorn at the beach".'));
  assertFalse(prompt.includes("The parent's opening idea"));
});

Deno.test("buildStoryPathSystemPrompt never ends the story on page 1 because the opening idea mentions an ending", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({
      input: { kind: "typed", speaker: "parent", text: "a bunny who finds a lost star, and we end the story with a bedtime hug" },
    }),
  );
  assertFalse(prompt.includes("the very last beat"));
  assertFalse(prompt.includes("unmistakable close"));
});

Deno.test("buildStoryPathSystemPrompt treats a blank opening input like the brief-only start", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({ input: { kind: "typed", speaker: "parent", text: "   " } }));
  assert(prompt.includes("Plan the path from the brief above."));
  assertFalse(prompt.includes("opening idea"));
});

Deno.test("buildStoryPathSystemPrompt asks for art prompts that name exactly the characters who appear", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("In artPrompt, name every character who appears by their bible name, and only those."));
});

Deno.test("buildStoryPageSystemPrompt asks for art prompts that name exactly the characters who appear", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("In artPrompt, name every character who appears by their bible name, and only those."));
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
