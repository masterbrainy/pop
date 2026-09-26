import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  STORY_PAGE_JSON_SCHEMA,
  STORY_PATH_JSON_SCHEMA,
  storyPageModelOutputSchema,
  storyPathModelOutputSchema,
} from "./story_path_schema.ts";
import { CHOICE_SYMBOLS, DEFAULT_CHOICE_SYMBOL } from "./choice_symbols.ts";

const question = {
  ask: "Will the kite fly to the tree or the pond?",
  kind: "choice",
  choices: [
    { label: "The tree", symbol: "tree.fill", direction: "The kite drifts into the old oak tree.", followsPath: true },
    { label: "The pond", symbol: "drop.fill", direction: "The kite lands softly on the pond.", followsPath: false },
  ],
};

function pathOutput(overrides: Record<string, unknown> = {}) {
  return {
    path: ["Maya finds a red kite in the meadow.", "Maya falls asleep holding the kite. The end."],
    isEnding: false,
    pageText: "Maya finds a red kite in the meadow.",
    artPrompt: "A young girl finding a red kite in a sunny meadow.",
    question,
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
    question,
    parentNote: null,
    ...overrides,
  };
}

Deno.test("storyPathModelOutputSchema accepts a well-formed path-mode response", () => {
  const result = storyPathModelOutputSchema.safeParse(pathOutput());
  assert(result.success);
  if (result.success) assertEquals(result.data.question.choices.length, 2);
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

Deno.test("storyPathModelOutputSchema defaults a missing question to an empty talk-only one", () => {
  const { question: _drop, ...rest } = pathOutput();
  const result = storyPathModelOutputSchema.safeParse(rest);
  assert(result.success);
  if (result.success) assertEquals(result.data.question, { ask: "", kind: "talkOnly", choices: [] });
});

Deno.test("storyPageModelOutputSchema maps an unknown symbol to the default instead of failing the page", () => {
  const result = storyPageModelOutputSchema.safeParse(pageOutput({
    question: { ...question, choices: [{ ...question.choices[0], symbol: "flame.fill.bogus" }, question.choices[1]] },
  }));
  assert(result.success);
  if (result.success) {
    assertEquals(result.data.question.choices[0].symbol, DEFAULT_CHOICE_SYMBOL);
    assertEquals(result.data.question.choices[1].symbol, "drop.fill");
  }
});

Deno.test("storyPageModelOutputSchema drops a malformed choice and tolerates a malformed question", () => {
  const withBadChoice = storyPageModelOutputSchema.safeParse(pageOutput({
    question: { ...question, choices: [{ label: "No direction" }, question.choices[1]] },
  }));
  assert(withBadChoice.success);
  if (withBadChoice.success) assertEquals(withBadChoice.data.question.choices.map((c) => c.label), ["The pond"]);

  const withBadQuestion = storyPageModelOutputSchema.safeParse(pageOutput({ question: "What colour is the kite?" }));
  assert(withBadQuestion.success);
  if (withBadQuestion.success) assertEquals(withBadQuestion.data.question.ask, "");

  const withBadKind = storyPageModelOutputSchema.safeParse(pageOutput({ question: { ...question, kind: "quiz" } }));
  assert(withBadKind.success);
  if (withBadKind.success) assertEquals(withBadKind.data.question.kind, "talkOnly");
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

type JsonSchemaNode = {
  type?: unknown;
  properties?: Record<string, JsonSchemaNode>;
  required?: string[];
  additionalProperties?: boolean;
  items?: JsonSchemaNode;
  enum?: string[];
};

/** OpenAI strict mode: every object lists every property as required and forbids extras. */
function assertStrictObjects(node: JsonSchemaNode, path: string): void {
  if (node.properties) {
    assertEquals([...(node.required ?? [])].sort(), Object.keys(node.properties).sort(), `${path}: required`);
    assertEquals(node.additionalProperties, false, `${path}: additionalProperties`);
    for (const [key, child] of Object.entries(node.properties)) assertStrictObjects(child, `${path}.${key}`);
  }
  if (node.items) assertStrictObjects(node.items, `${path}[]`);
}

Deno.test("both strict JSON schemas carry the question object and stay strict-mode valid", () => {
  for (const schema of [STORY_PATH_JSON_SCHEMA, STORY_PAGE_JSON_SCHEMA]) {
    const root = schema.schema as unknown as JsonSchemaNode;
    assertStrictObjects(root, schema.name);
    assertFalse("readingQuestion" in (root.properties ?? {}));
    const questionNode = root.properties!.question;
    assertEquals(questionNode.properties!.kind.enum, ["choice", "open", "talkOnly"]);
    const symbolNode = questionNode.properties!.choices.items!.properties!.symbol;
    assertEquals(symbolNode.enum, [...CHOICE_SYMBOLS]);
  }
});
