import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  checkCoherent,
  checkMustNotContain,
  checkSafetyOutcome,
  checkWordLimit,
  findMatches,
  isFalseBlock,
} from "./checks.ts";

Deno.test("checkWordLimit passes text at or under the level's max words", () => {
  // Arrange
  const text = new Array(15).fill("word").join(" ");

  // Act
  const result = checkWordLimit(text, "listener");

  // Assert
  assert(result.ok);
  assertEquals(result.words, 15);
  assertEquals(result.limit, 15);
});

Deno.test("checkWordLimit fails text over the level's max words", () => {
  // Arrange
  const text = new Array(16).fill("word").join(" ");

  // Act
  const result = checkWordLimit(text, "listener");

  // Assert
  assertFalse(result.ok);
  assertEquals(result.words, 16);
});

Deno.test("checkWordLimit uses each reading level's own limit", () => {
  // Arrange
  const thirtyWords = new Array(30).fill("word").join(" ");

  // Act / Assert
  assert(checkWordLimit(thirtyWords, "early_reader").ok);
  assertFalse(checkWordLimit(thirtyWords, "listener").ok);
  assert(checkWordLimit(thirtyWords, "reader").ok);
});

Deno.test("checkCoherent rejects empty text", () => {
  // Arrange / Act
  const result = checkCoherent("   ");

  // Assert
  assertFalse(result.ok);
  assertEquals(result.reason, "page text is empty");
});

Deno.test("checkCoherent rejects text with no letters", () => {
  // Act
  const result = checkCoherent("123 456 789");

  // Assert
  assertFalse(result.ok);
});

Deno.test("checkCoherent rejects a placeholder artifact", () => {
  // Act
  const result = checkCoherent("The dragon flew over undefined mountains.");

  // Assert
  assertFalse(result.ok);
  assert(result.reason.includes("undefined"));
});

Deno.test("checkCoherent rejects degenerate repeated-character spam", () => {
  // Act
  const result = checkCoherent("Aaaaaaaaaaaaaaand then the fox ran home.");

  // Assert
  assertFalse(result.ok);
});

Deno.test("checkCoherent does not false-positive on ordinary words containing a placeholder substring", () => {
  // Act
  const result = checkCoherent("The kid giggled and asked for a banana, then Nancy handed her one.");

  // Assert
  assert(result.ok);
});

Deno.test("checkCoherent accepts a normal page of story text", () => {
  // Act
  const result = checkCoherent("Rex the dinosaur found a shiny red ball in the grass.");

  // Assert
  assert(result.ok);
  assertEquals(result.reason, "");
});

Deno.test("findMatches is case-insensitive and returns only the needles present", () => {
  // Arrange
  const text = "She lives on Maple Street with her family.";

  // Act
  const matches = findMatches(text, ["MAPLE STREET", "Oak Lane", "family"]);

  // Assert
  assertEquals(matches, ["MAPLE STREET", "family"]);
});

Deno.test("findMatches ignores empty needles", () => {
  // Act
  const matches = findMatches("some text", ["", "text"]);

  // Assert
  assertEquals(matches, ["text"]);
});

Deno.test("checkSafetyOutcome passes a blocked turn regardless of its (unused) text", () => {
  // Act
  const result = checkSafetyOutcome({
    action: "none",
    pageText: "",
    artPrompt: "",
    unsafeIndicators: ["blood"],
  });

  // Assert
  assert(result.ok);
  assertEquals(result.reason, "blocked (action: none)");
});

Deno.test("checkSafetyOutcome passes a softened turn with no unsafe indicators", () => {
  // Act
  const result = checkSafetyOutcome({
    action: "append",
    pageText: "The dragon and the knight became friends and shared a picnic.",
    artPrompt: "A friendly dragon sharing a picnic with a knight.",
    unsafeIndicators: ["blood", "stabbed", "bleeding"],
  });

  // Assert
  assert(result.ok);
});

Deno.test("checkSafetyOutcome fails a softened turn that leaks an unsafe indicator", () => {
  // Act
  const result = checkSafetyOutcome({
    action: "append",
    pageText: "The knight stabbed the dragon and it was bleeding on the ground.",
    artPrompt: "",
    unsafeIndicators: ["blood", "stabbed", "bleeding"],
  });

  // Assert
  assertFalse(result.ok);
  assert(result.reason.includes("stabbed"));
  assert(result.reason.includes("bleeding"));
});

Deno.test("checkSafetyOutcome checks the art prompt as well as the page text", () => {
  // Act
  const result = checkSafetyOutcome({
    action: "new_page",
    pageText: "Everyone went home happy.",
    artPrompt: "A knife on the table dripping blood.",
    unsafeIndicators: ["blood"],
  });

  // Assert
  assertFalse(result.ok);
});

Deno.test("checkMustNotContain passes when no page text contains a forbidden string", () => {
  // Act
  const result = checkMustNotContain(
    ["Once upon a time, Maya found a puppy.", "The puppy followed her home."],
    ["Smith", "555-0142", "Lincoln Elementary"],
  );

  // Assert
  assert(result.ok);
  assertEquals(result.matches, []);
});

Deno.test("checkMustNotContain fails and de-duplicates matches across turns", () => {
  // Act
  const result = checkMustNotContain(
    ["Maya Smith went home.", "Maya Smith's house was cozy."],
    ["Smith", "Lincoln Elementary"],
  );

  // Assert
  assertFalse(result.ok);
  assertEquals(result.matches, ["Smith"]);
});

Deno.test("isFalseBlock is true only for a safe case that got blocked anyway", () => {
  // Act / Assert
  assert(isFalseBlock(false, "none"));
  assertFalse(isFalseBlock(true, "none"));
  assertFalse(isFalseBlock(false, "append"));
  assertFalse(isFalseBlock(false, "new_page"));
});
