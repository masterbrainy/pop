import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

const kid = { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] };
const bible = { title: null, setting: "", characters: [], directions: [], path: [] };

Deno.test("requestSchema accepts a well-formed title request without current/input", () => {
  const result = requestSchema.safeParse({
    mode: "title",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    bible,
    pages: [{ index: 0, text: "Once upon a time" }],
  });
  assert(result.success);
});

Deno.test("requestSchema rejects mode 'turn' (removed once the app moved to path/page)", () => {
  const result = requestSchema.safeParse({
    mode: "turn",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief: { interests: [], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible,
    pages: [],
    current: { index: 0, text: "" },
    input: { kind: "typed", speaker: "parent", text: "Once upon a time" },
  });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects an unknown mode", () => {
  const result = requestSchema.safeParse({ mode: "rewind", bookId: "123e4567-e89b-12d3-a456-426614174000", kid, bible, pages: [] });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a non-uuid bookId", () => {
  const result = requestSchema.safeParse({
    mode: "title",
    bookId: "not-a-uuid",
    kid,
    bible,
    pages: [],
  });
  assertFalse(result.success);
});

const brief = { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" };
const settings = { avoidTopics: [] };

Deno.test("requestSchema accepts a well-formed path request at the start (no input)", () => {
  const result = requestSchema.safeParse({
    mode: "path",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief,
    settings,
    bible,
    pages: [],
    index: 0,
  });
  assert(result.success);
});

Deno.test("requestSchema accepts a well-formed path request with a direction", () => {
  const result = requestSchema.safeParse({
    mode: "path",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief,
    settings,
    bible: { ...bible, path: ["Beat 0"] },
    pages: [{ index: 0, text: "Once upon a time" }],
    index: 1,
    input: { kind: "typed", speaker: "parent", text: "wake the dragon up" },
  });
  assert(result.success);
});

Deno.test("requestSchema rejects a path request with input.kind 'continue' (no page to continue)", () => {
  const result = requestSchema.safeParse({
    mode: "path",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief,
    settings,
    bible,
    pages: [],
    index: 0,
    input: { kind: "continue", speaker: "parent", text: "" },
  });
  assertFalse(result.success);
});

Deno.test("requestSchema accepts a well-formed page request (no input)", () => {
  const result = requestSchema.safeParse({
    mode: "page",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief,
    settings,
    bible: { ...bible, path: ["Beat 0", "Beat 1"] },
    pages: [{ index: 0, text: "Once upon a time" }],
    index: 1,
  });
  assert(result.success);
});

const pathBase = {
  mode: "path",
  bookId: "123e4567-e89b-12d3-a456-426614174000",
  kid: { ...kid, interests: [] },
  settings,
  bible,
  pages: [],
  index: 0,
};

Deno.test("requestSchema accepts a guided-setup brief with tiles, text answers, mood and purpose", () => {
  const result = requestSchema.safeParse({
    ...pathBase,
    brief: {
      interests: [],
      realMoment: null,
      teach: null,
      language: "en",
      hero: { tile: "dragon" },
      place: { text: "Grandma's garden", via: "speech" },
      problem: null,
      mood: "silly",
      purpose: "bedtime",
    },
  });
  assert(result.success);
});

Deno.test("requestSchema accepts an unknown tile id (the prompt ignores it) but rejects a malformed answer", () => {
  assert(requestSchema.safeParse({ ...pathBase, brief: { ...brief, hero: { tile: "hoverboard" } } }).success);
  assertFalse(requestSchema.safeParse({ ...pathBase, brief: { ...brief, hero: "a dragon" } }).success);
  assertFalse(requestSchema.safeParse({ ...pathBase, brief: { ...brief, place: { text: "x", via: "typed", tile: "castle" } } }).success);
  assertFalse(requestSchema.safeParse({ ...pathBase, brief: { ...brief, problem: { text: "", via: "typed" } } }).success);
});

Deno.test("requestSchema accepts a tapped choice and rejects one over 120 characters", () => {
  const withChoice = (text: string) => ({
    ...pathBase,
    brief,
    bible: { ...bible, path: ["Beat 0"] },
    index: 1,
    input: { kind: "choice", speaker: "kid", text },
  });
  assert(requestSchema.safeParse(withChoice("The dragon looks under the bed.")).success);
  assertFalse(requestSchema.safeParse(withChoice("a".repeat(121))).success);
});

Deno.test("requestSchema rejects a path or page request with a negative index", () => {
  const base = { mode: "path", bookId: "123e4567-e89b-12d3-a456-426614174000", kid, brief, settings, bible, pages: [] };
  assertFalse(requestSchema.safeParse({ ...base, index: -1 }).success);
});
