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
