import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  countWords,
  describeReadingLevelForPrompt,
  isReadingLevel,
  readingLevelLimits,
  withinWordLimit,
} from "./reading_levels.ts";

Deno.test("readingLevelLimits matches PRD §8.7 for every level", () => {
  assertEquals(readingLevelLimits("listener"), {
    ages: "3-4",
    maxWords: 15,
    minSentences: 1,
    maxSentences: 2,
  });
  assertEquals(readingLevelLimits("early_reader"), {
    ages: "5-6",
    maxWords: 30,
    minSentences: 2,
    maxSentences: 3,
  });
  assertEquals(readingLevelLimits("reader"), {
    ages: "7-8",
    maxWords: 60,
    minSentences: 1,
    maxSentences: 5,
  });
});

Deno.test("isReadingLevel accepts only the three known levels", () => {
  assert(isReadingLevel("listener"));
  assert(isReadingLevel("early_reader"));
  assert(isReadingLevel("reader"));
  assertFalse(isReadingLevel("toddler"));
  assertFalse(isReadingLevel(""));
});

Deno.test("countWords counts whitespace-separated words and ignores edges", () => {
  assertEquals(countWords("Rex the dinosaur went home."), 5);
  assertEquals(countWords("  spaced   out   words  "), 3);
  assertEquals(countWords(""), 0);
  assertEquals(countWords("   "), 0);
});

Deno.test("withinWordLimit enforces each level's max word count", () => {
  const fifteenWords = new Array(15).fill("word").join(" ");
  const sixteenWords = new Array(16).fill("word").join(" ");
  assert(withinWordLimit(fifteenWords, "listener"));
  assertFalse(withinWordLimit(sixteenWords, "listener"));
  assert(withinWordLimit(sixteenWords, "early_reader"));
});

Deno.test("describeReadingLevelForPrompt mentions the word cap and ages", () => {
  const text = describeReadingLevelForPrompt("early_reader");
  assert(text.includes("30"));
  assert(text.includes("5-6"));
});
