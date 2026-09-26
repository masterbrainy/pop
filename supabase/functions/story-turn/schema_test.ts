import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

const kid = { firstName: "Maya", readingLevel: "early_reader", interests: ["dinosaurs"] };
const bible = { title: null, setting: "", characters: [], directions: [], path: [] };

Deno.test("requestSchema accepts a well-formed turn request", () => {
  const result = requestSchema.safeParse({
    mode: "turn",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible,
    pages: [],
    current: { index: 0, text: "" },
    input: { kind: "typed", speaker: "parent", text: "Once upon a time" },
  });
  assert(result.success);
});

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

Deno.test("requestSchema rejects a turn request missing input", () => {
  const result = requestSchema.safeParse({
    mode: "turn",
    bookId: "123e4567-e89b-12d3-a456-426614174000",
    kid,
    brief: { interests: [], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible,
    pages: [],
    current: { index: 0, text: "" },
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

Deno.test("requestSchema rejects a path or page request with a negative index", () => {
  const base = { mode: "path", bookId: "123e4567-e89b-12d3-a456-426614174000", kid, brief, settings, bible, pages: [] };
  assertFalse(requestSchema.safeParse({ ...base, index: -1 }).success);
});
