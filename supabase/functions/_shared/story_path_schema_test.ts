import { assert, assertFalse } from "jsr:@std/assert@1";
import { storyPageModelOutputSchema, storyPathModelOutputSchema } from "./story_path_schema.ts";

function pathOutput(overrides: Record<string, unknown> = {}) {
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

function pageOutput(overrides: Record<string, unknown> = {}) {
  return {
    pageText: "Maya finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    readingQuestion: "What colour is the kite?",
    parentNote: null,
    ...overrides,
  };
}

Deno.test("storyPathModelOutputSchema accepts a well-formed path-mode response", () => {
  const result = storyPathModelOutputSchema.safeParse(pathOutput());
  assert(result.success);
});

Deno.test("storyPathModelOutputSchema requires at least one beat in path", () => {
  const result = storyPathModelOutputSchema.safeParse(pathOutput({ path: [] }));
  assertFalse(result.success);
});

Deno.test("storyPathModelOutputSchema rejects a missing isEnding", () => {
  const { isEnding: _drop, ...rest } = pathOutput();
  const result = storyPathModelOutputSchema.safeParse(rest);
  assertFalse(result.success);
});

Deno.test("storyPathModelOutputSchema defaults readingQuestion to an empty string", () => {
  const { readingQuestion: _drop, ...rest } = pathOutput();
  const result = storyPathModelOutputSchema.safeParse(rest);
  assert(result.success);
  if (result.success) assert(result.data.readingQuestion === "");
});

Deno.test("storyPageModelOutputSchema accepts a well-formed page-mode response", () => {
  const result = storyPageModelOutputSchema.safeParse(pageOutput());
  assert(result.success);
});

Deno.test("storyPageModelOutputSchema rejects a missing pageText", () => {
  const { pageText: _drop, ...rest } = pageOutput();
  const result = storyPageModelOutputSchema.safeParse(rest);
  assertFalse(result.success);
});

Deno.test("storyPageModelOutputSchema has no path or bible-update fields (no re-planning)", () => {
  const result = storyPageModelOutputSchema.safeParse(pageOutput({ path: ["should be ignored"] }));
  assert(result.success);
  if (result.success) assertFalse("path" in result.data);
});
