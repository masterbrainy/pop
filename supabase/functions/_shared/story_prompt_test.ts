import { assert, assertFalse } from "jsr:@std/assert@1";
import { buildStoryTurnSystemPrompt, buildTitlePrompt, type StoryTurnPromptInput } from "./story_prompt.ts";
import { storyModelOutputSchema } from "./story_schema.ts";

function baseInput(overrides: Partial<StoryTurnPromptInput> = {}): StoryTurnPromptInput {
  return {
    kid: { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [] },
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
      bible: { title: null, setting: "a jungle", characters: [], directions: ["add a friendly dragon"] },
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
    { title: null, setting: "a quiet meadow", characters: [], directions: [] },
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
