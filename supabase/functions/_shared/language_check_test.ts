import { assert, assertFalse } from "jsr:@std/assert@1";
import { hasForeignScriptText } from "./language_check.ts";

Deno.test("hasForeignScriptText passes plain English text", () => {
  assertFalse(hasForeignScriptText("A friendly fox found a shiny red kite.", "en"));
});

Deno.test("hasForeignScriptText passes digits, punctuation and emoji in an 'en' story", () => {
  assertFalse(hasForeignScriptText("Rex counted 3 stars: one, two, three! 🌟", "en"));
});

Deno.test("hasForeignScriptText catches a Cyrillic word dropped into an 'en' story", () => {
  assert(hasForeignScriptText("A friendly fox is рядом, and both look surprised.", "en"));
});

Deno.test("hasForeignScriptText catches other non-Latin scripts too (CJK, Arabic)", () => {
  assert(hasForeignScriptText("The dragon said 你好 to the kite.", "en"));
  assert(hasForeignScriptText("The dragon said مرحبا to the kite.", "en"));
});

Deno.test("hasForeignScriptText allows accented Latin letters (still Latin script)", () => {
  assertFalse(hasForeignScriptText("Cafe au lait and a naive little fox: café, naïve.", "en"));
});

Deno.test("hasForeignScriptText skips the check entirely for a non-'en' language", () => {
  assertFalse(hasForeignScriptText("La zorra encontró una cometa roja.", "es"));
  assertFalse(hasForeignScriptText("Мама читает книгу.", "ru"));
});

Deno.test("hasForeignScriptText treats an empty string as safe", () => {
  assertFalse(hasForeignScriptText("", "en"));
});

// Regression (R-41/ending-reader false block): a model can emit typographic
// punctuation the safety gate must never mistake for a foreign-script leak —
// curly quotes, an em dash, an accented name, an ellipsis, emoji, and a
// modifier letter apostrophe (U+02BC), which is categorized as a Letter but
// belongs to the script-neutral "Common" script, not Latin.
Deno.test("hasForeignScriptText passes curly quotes, em dashes, ellipses and accented names", () => {
  assertFalse(hasForeignScriptText("Elena said, ‘Let’s go!’", "en"));
  assertFalse(hasForeignScriptText("Elena went home—slowly, then stopped.", "en"));
  assertFalse(hasForeignScriptText("Wait… what happens next?", "en"));
  assertFalse(hasForeignScriptText("Zoë and Renée went sailing together.", "en"));
  assertFalse(hasForeignScriptText("The end ✨", "en"));
});

Deno.test("hasForeignScriptText does not flag a modifier letter apostrophe as a foreign script (R-41 root cause)", () => {
  // Some models write a contraction with U+02BC MODIFIER LETTER APOSTROPHE
  // instead of a straight or curly quote. It's categorized as a Letter, but
  // its script is "Common" (shared across every script), not a real foreign
  // script, so it must pass.
  assertFalse(hasForeignScriptText("Elenaʼs boat finally reached the island.", "en"));
});

Deno.test("hasForeignScriptText still catches a genuine foreign-script leak alongside safe punctuation", () => {
  assert(hasForeignScriptText("Elena’s friend said ‘привет’ with a smile.", "en"));
});

Deno.test("hasForeignScriptText allows the kid's own name and bible character names even in a non-Latin script", () => {
  assertFalse(hasForeignScriptText("李明 waved to Дима by the lake.", "en", ["李明", "Дима"]));
});

Deno.test("hasForeignScriptText still catches a real leak when allowedNames are given", () => {
  assert(hasForeignScriptText("李明 said привет to Дима.", "en", ["李明", "Дима"]));
});

Deno.test("hasForeignScriptText matches an allowed name case-insensitively", () => {
  assertFalse(hasForeignScriptText("дима played in the meadow.", "en", ["Дима"]));
});
