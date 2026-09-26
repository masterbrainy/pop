import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  briefAnswerSchema,
  characterSchema,
  directionInputSchema,
  kidSchema,
  readingLevelSchema,
  storyBibleSchema,
  storyBriefSchema,
  uuidSchema,
  zodIssueSummary,
} from "./schemas.ts";

Deno.test("readingLevelSchema accepts the three known levels only", () => {
  assert(readingLevelSchema.safeParse("listener").success);
  assert(readingLevelSchema.safeParse("early_reader").success);
  assert(readingLevelSchema.safeParse("reader").success);
  assertFalse(readingLevelSchema.safeParse("toddler").success);
});

Deno.test("uuidSchema rejects non-uuid strings", () => {
  assert(uuidSchema.safeParse("2f0b1a3e-6a9a-4b7a-9c6e-2a2a2a2a2a2a").success);
  assertFalse(uuidSchema.safeParse("not-a-uuid").success);
});

Deno.test("kidSchema defaults interests to an empty array and trims the name", () => {
  const result = kidSchema.parse({
    firstName: "  Sara  ",
    readingLevel: "early_reader",
  });
  assertEquals(result.firstName, "Sara");
  assertEquals(result.interests, []);
});

Deno.test("kidSchema rejects an empty first name", () => {
  const result = kidSchema.safeParse({ firstName: "", readingLevel: "reader" });
  assertFalse(result.success);
});

Deno.test("storyBriefSchema defaults language to en and allows null realMoment/teach", () => {
  const result = storyBriefSchema.parse({ interests: ["dinosaurs"] });
  assertEquals(result.language, "en");
  assertEquals(result.realMoment, undefined);
});

Deno.test("characterSchema requires id, name and description", () => {
  assertFalse(characterSchema.safeParse({ id: "c1", name: "Rex" }).success);
  assert(
    characterSchema.safeParse({
      id: "c1",
      name: "Rex",
      description: "A friendly green dinosaur",
    }).success,
  );
});

Deno.test("storyBibleSchema defaults path to an empty array (backward compatible with a bible sent before P-04)", () => {
  const result = storyBibleSchema.parse({ setting: "", characters: [], directions: [] });
  assertEquals(result.path, []);
});

Deno.test("storyBibleSchema accepts a path of beats up to the 12-beat cap", () => {
  const path = Array.from({ length: 12 }, (_, i) => `Beat ${i}`);
  const result = storyBibleSchema.safeParse({ setting: "", characters: [], directions: [], path });
  assert(result.success);
});

Deno.test("storyBibleSchema rejects more than 12 path beats", () => {
  const path = Array.from({ length: 13 }, (_, i) => `Beat ${i}`);
  const result = storyBibleSchema.safeParse({ setting: "", characters: [], directions: [], path });
  assertFalse(result.success);
});

Deno.test("storyBibleSchema rejects a path beat over 300 characters", () => {
  const path = ["a".repeat(301)];
  const result = storyBibleSchema.safeParse({ setting: "", characters: [], directions: [], path });
  assertFalse(result.success);
});

Deno.test("directionInputSchema accepts speech and typed but not continue", () => {
  assert(directionInputSchema.safeParse({ kind: "typed", speaker: "parent", text: "wake the dragon up" }).success);
  assert(directionInputSchema.safeParse({ kind: "speech", speaker: "kid", text: "add a puppy" }).success);
  assertFalse(directionInputSchema.safeParse({ kind: "continue", speaker: "parent", text: "" }).success);
});

// --- IMP-24 guided setup answers / IMP-25 choice input ---

Deno.test("briefAnswerSchema accepts a tile or a trimmed text answer with its source", () => {
  assert(briefAnswerSchema.safeParse({ tile: "dragon" }).success);
  const text = briefAnswerSchema.parse({ text: "  a purple owl  ", via: "speech" });
  assertEquals(text, { text: "a purple owl", via: "speech" });
});

Deno.test("briefAnswerSchema rejects mixed, empty, overlong and unknown-source answers", () => {
  assertFalse(briefAnswerSchema.safeParse({ tile: "dragon", text: "x", via: "typed" }).success);
  assertFalse(briefAnswerSchema.safeParse({ tile: "   " }).success);
  assertFalse(briefAnswerSchema.safeParse({ text: "   ", via: "typed" }).success);
  assertFalse(briefAnswerSchema.safeParse({ text: "a".repeat(81), via: "typed" }).success);
  assertFalse(briefAnswerSchema.safeParse({ text: "owl", via: "telepathy" }).success);
  assertFalse(briefAnswerSchema.safeParse({ text: "owl" }).success);
});

Deno.test("storyBriefSchema keeps an old app's brief valid with no setup fields", () => {
  const result = storyBriefSchema.parse({ interests: [], realMoment: null, teach: null, language: "en" });
  assertEquals(result.hero, undefined);
  assertEquals(result.mood, undefined);
});

Deno.test("storyBriefSchema accepts hero/place/problem answers, mood and purpose", () => {
  const result = storyBriefSchema.parse({
    interests: [],
    language: "en",
    hero: { tile: "dragon" },
    place: { text: "Grandma's garden", via: "typed" },
    problem: null,
    mood: "cosy",
    purpose: "bedtime",
  });
  assertEquals(result.hero, { tile: "dragon" });
  assertEquals(result.place, { text: "Grandma's garden", via: "typed" });
  assertEquals(result.problem, null);
  assertEquals(result.mood, "cosy");
  assertEquals(result.purpose, "bedtime");
});

Deno.test("storyBriefSchema rejects an unknown mood or purpose", () => {
  assertFalse(storyBriefSchema.safeParse({ interests: [], mood: "spooky" }).success);
  assertFalse(storyBriefSchema.safeParse({ interests: [], purpose: "homework" }).success);
});

Deno.test("directionInputSchema accepts a choice of at most 120 characters", () => {
  assert(directionInputSchema.safeParse({ kind: "choice", speaker: "kid", text: "The dragon looks under the bed." }).success);
  assert(directionInputSchema.safeParse({ kind: "choice", speaker: "kid", text: "a".repeat(120) }).success);
});

Deno.test("directionInputSchema rejects a choice over 120 characters, but not a long typed direction", () => {
  const result = directionInputSchema.safeParse({ kind: "choice", speaker: "kid", text: "a".repeat(121) });
  assertFalse(result.success);
  if (!result.success) assert(zodIssueSummary(result.error).startsWith("text:"));
  assert(directionInputSchema.safeParse({ kind: "typed", speaker: "parent", text: "a".repeat(121) }).success);
});

Deno.test("zodIssueSummary produces a readable path: message string", () => {
  const result = kidSchema.safeParse({ firstName: "", readingLevel: "reader" });
  assert(!result.success);
  if (!result.success) {
    const summary = zodIssueSummary(result.error);
    assert(summary.startsWith("firstName:"));
  }
});
