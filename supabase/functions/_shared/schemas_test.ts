import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  characterSchema,
  directionInputSchema,
  kidSchema,
  readingLevelSchema,
  storyBibleSchema,
  storyBriefSchema,
  storyInputSchema,
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
    firstName: "  Maya  ",
    readingLevel: "early_reader",
  });
  assertEquals(result.firstName, "Maya");
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

Deno.test("storyInputSchema restricts kind and speaker to known enums", () => {
  assert(
    storyInputSchema.safeParse({ kind: "typed", speaker: "parent", text: "hi" })
      .success,
  );
  assertFalse(
    storyInputSchema.safeParse({ kind: "sung", speaker: "parent", text: "hi" })
      .success,
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

Deno.test("zodIssueSummary produces a readable path: message string", () => {
  const result = kidSchema.safeParse({ firstName: "", readingLevel: "reader" });
  assert(!result.success);
  if (!result.success) {
    const summary = zodIssueSummary(result.error);
    assert(summary.startsWith("firstName:"));
  }
});
