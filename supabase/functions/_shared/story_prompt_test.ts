import { assert, assertFalse } from "jsr:@std/assert@1";
import {
  buildStoryPageSystemPrompt,
  buildStoryPathSystemPrompt,
  buildStoryTurnSystemPrompt,
  buildTitlePrompt,
  type StoryPagePromptInput,
  type StoryPathPromptInput,
  type StoryTurnPromptInput,
} from "./story_prompt.ts";
import { storyModelOutputSchema } from "./story_schema.ts";

function baseInput(overrides: Partial<StoryTurnPromptInput> = {}): StoryTurnPromptInput {
  return {
    kid: { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: [] },
    pages: [],
    current: { index: 0, text: "" },
    input: { kind: "typed", speaker: "parent", text: "Once upon a time" },
    ...overrides,
  };
}

Deno.test("buildStoryTurnSystemPrompt includes the kid's name, interests and reading-level limits", () => {
  const prompt = buildStoryTurnSystemPrompt(baseInput());
  assert(prompt.includes("Maya"));
  assert(prompt.includes("dinosaurs"));
  assert(prompt.includes("30")); // early_reader max words
});

Deno.test("buildStoryTurnSystemPrompt mentions the real moment and asks for a reassuring tone only when present", () => {
  const withMoment = buildStoryTurnSystemPrompt(
    baseInput({ brief: { interests: [], realMoment: "starting school", teach: null, language: "en" } }),
  );
  assert(withMoment.includes("starting school"));
  assert(withMoment.includes("reassuringly"));

  const without = buildStoryTurnSystemPrompt(baseInput());
  assertFalse(without.includes("reassuringly"));
});

Deno.test("buildStoryTurnSystemPrompt lists avoided topics only when settings has some", () => {
  const withAvoid = buildStoryTurnSystemPrompt(
    baseInput({ settings: { avoidTopics: ["monsters"] } }),
  );
  assert(withAvoid.includes("monsters"));

  const without = buildStoryTurnSystemPrompt(baseInput());
  assertFalse(without.includes("Never include these topics"));
});

Deno.test("buildStoryTurnSystemPrompt carries every prior direction forward", () => {
  const prompt = buildStoryTurnSystemPrompt(
    baseInput({
      bible: { title: null, setting: "a jungle", characters: [], directions: ["add a friendly dragon"], path: [] },
    }),
  );
  assert(prompt.includes("add a friendly dragon"));
  assert(prompt.includes("a jungle"));
});

Deno.test("buildStoryTurnSystemPrompt never omits the personal-details or safety rubric instructions", () => {
  const prompt = buildStoryTurnSystemPrompt(baseInput());
  assert(prompt.includes("surnames"));
  assert(prompt.includes("Kid-safety rubric"));
});

Deno.test("buildStoryTurnSystemPrompt echoes this turn's input kind, speaker and text", () => {
  const prompt = buildStoryTurnSystemPrompt(
    baseInput({ input: { kind: "continue", speaker: "kid", text: "and then a rainbow" } }),
  );
  assert(prompt.includes("continue"));
  assert(prompt.includes("kid"));
  assert(prompt.includes("and then a rainbow"));
});

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

Deno.test("storyModelOutputSchema accepts a well-formed model response", () => {
  const result = storyModelOutputSchema.safeParse({
    action: "append",
    pageText: "Rex found a shiny rock.",
    artPrompt: "A green dinosaur admiring a shiny rock",
    breakSuggested: false,
    bibleTitle: null,
    bibleSetting: "a sunny valley",
    bibleCharacters: [{ id: "rex", name: "Rex", description: "a friendly green dinosaur" }],
    bibleDirections: [],
    parentNote: null,
  });
  assert(result.success);
});

Deno.test("storyModelOutputSchema rejects an unknown action", () => {
  const result = storyModelOutputSchema.safeParse({
    action: "delete_page",
    pageText: "",
    artPrompt: "",
    breakSuggested: false,
    bibleTitle: null,
    bibleSetting: "",
    bibleCharacters: [],
    bibleDirections: [],
    parentNote: null,
  });
  assertFalse(result.success);
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
