import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  characterSchema,
  kidSchema,
  readingLevelSchema,
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

Deno.test("zodIssueSummary produces a readable path: message string", () => {
  const result = kidSchema.safeParse({ firstName: "", readingLevel: "reader" });
  assert(!result.success);
  if (!result.success) {
    const summary = zodIssueSummary(result.error);
    assert(summary.startsWith("firstName:"));
  }
});
